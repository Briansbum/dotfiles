{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.tailscaleServe;

  serveCmd = name: svc:
    let
      httpsPort = if svc.path != null
        then (if svc.tsPort != null then svc.tsPort else 443)
        else svc.tsPort;
      args = if svc.tcp
        then "--bg --tcp=${toString svc.tsPort} localhost:${toString svc.localPort}"
        else if svc.path != null
        then "--bg --https=${toString httpsPort} --set-path=/${removePrefix "/" svc.path} http://localhost:${toString svc.localPort}"
        else "--bg --https=${toString httpsPort} http://localhost:${toString svc.localPort}";
      verb = if svc.funnel then "funnel" else "serve";
    in "${config.services.tailscale.package}/bin/tailscale ${verb} ${args}";

  afterServices = unique (concatMap (svc:
    optional (svc.afterService != null) "${svc.afterService}.service"
  ) (attrValues cfg));

in {
  options.services.tailscaleServe = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        localPort = mkOption {
          type = types.port;
          description = "Local port the service listens on.";
        };

        path = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Serve under https://hostname/path instead of a dedicated port.
            When null, uses a dedicated --https port (falls back to localPort).
          '';
        };

        tsPort = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = ''
            Tailscale HTTPS port.
            - When path is null, defaults to localPort if unset.
            - When path is set, defaults to 443 if unset.
          '';
        };

        afterService = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Systemd service to wait for before starting the proxy.";
        };

        funnel = mkOption {
          type = types.bool;
          default = false;
          description = "Use `tailscale funnel` instead of `tailscale serve`.";
        };

        tcp = mkOption {
          type = types.bool;
          default = false;
          description = "Use --tcp instead of --https (raw TCP passthrough, no TLS termination).";
        };
      };
    });
    default = {};
    description = "Tailscale serve proxies for local services.";
  };

  config = mkIf (cfg != {}) {
    assertions = mapAttrsToList (name: svc: {
      assertion = svc.path != null || svc.tsPort != null;
      message = "services.tailscaleServe.${name}: must set either 'path' or 'tsPort'.";
    }) cfg;

    # Single service runs all serve commands sequentially — avoids races
    # when multiple proxies try to update the Tailscale serve config in parallel.
    systemd.services.tailscale-serve = {
      description = "tailscale serve proxies";
      wantedBy = [ "multi-user.target" ];
      wants    = [ "network-online.target" ];
      after    = [ "network-online.target" "tailscaled.service" ] ++ afterServices;

      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "tailscale-serve-all" (
          concatStringsSep "\n" (mapAttrsToList serveCmd cfg)
        );
      };
    };
  };
}
