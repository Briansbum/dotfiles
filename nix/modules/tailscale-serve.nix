{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.tailscaleServe;
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
            Tailscale HTTPS port. Only used when path is null.
            Defaults to localPort if unset.
          '';
        };

        afterService = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Systemd service to wait for before starting the proxy.";
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

    systemd.services = mapAttrs' (name: svc:
      let
        serveCmd = if svc.path != null
          then "--https=443 --set-path=/${removePrefix "/" svc.path} http://localhost:${toString svc.localPort}"
          else "--https=${toString svc.tsPort} http://localhost:${toString svc.localPort}";
        after = [ "network-online.target" "tailscaled.service" ]
          ++ optional (svc.afterService != null) "${svc.afterService}.service";
      in nameValuePair "${name}-ts" {
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        inherit after;
        description = "tailscale proxy for ${name}";

        serviceConfig = {
          ExecStart = "${config.services.tailscale.package}/bin/tailscale serve ${serveCmd}";
          Restart = "always";
          RestartSec = 3;
          Type = "oneshot";
          RemainAfterExit = true;
        };
      }
    ) cfg;
  };
}
