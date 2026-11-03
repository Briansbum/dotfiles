{
  config,
  lib,
  ...
}:
let
  cfg = config.services.alloy-host;
  partialEtc = lib.listToAttrs (lib.imap0
    (index: partial: {
      name = "alloy/10-vm-${toString index}.alloy";
      value = {
        source = partial;
        mode = "0644";
      };
    })
    cfg.configPartials);
in
{
  options.services.alloy-host = {
    enable = lib.mkEnableOption "Grafana Alloy shipping host metrics and journal logs to Grafana Cloud";
    configFile = lib.mkOption {
      type = lib.types.path;
      description = "Base Alloy configuration for this host.";
    };
    configPartials = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Alloy configuration fragments installed alongside configFile in the
        Alloy configuration directory. Service VM definitions can expose
        Prometheus/OTel health endpoints as fragments.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."alloy_env" = {
      owner = "alloy";
      group = "alloy";
      mode = "0440";
      restartUnits = [ "alloy.service" ];
    };

    users.users.alloy = {
      isSystemUser = true;
      group = "alloy";
      extraGroups = [ "systemd-journal" ];
    };
    users.groups.alloy = { };

    services.alloy = {
      enable = true;
      configPath = "/etc/alloy";
      environmentFile = config.sops.secrets.alloy_env.path;
      extraFlags = [
        "--stability.level=generally-available"
        "--server.http.listen-addr=127.0.0.1:12345"
        "--disable-reporting"
      ];
    };

    systemd.services.alloy.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "alloy";
      Group = lib.mkForce "alloy";
    };

    # Alloy loads every *.alloy file in a configuration directory. Keep the
    # base config and VM fragments as separate files so the deployed paths
    # match the directory-loading behavior of `alloy run /etc/alloy`.
    environment.etc = {
      "alloy/00-base.alloy" = {
        source = cfg.configFile;
        mode = "0644";
      };
    } // partialEtc;
  };
}
