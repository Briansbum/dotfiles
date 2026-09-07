{
  config,
  lib,
  ...
}:
let
  cfg = config.services.alloy-host;
in
{
  options.services.alloy-host = {
    enable = lib.mkEnableOption "Grafana Alloy shipping host metrics and journal logs to Grafana Cloud";
    configFile = lib.mkOption {
      type = lib.types.path;
      description = "Alloy configuration for this host, installed as /etc/alloy/config.alloy.";
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

    environment.etc."alloy/config.alloy" = {
      source = cfg.configFile;
      mode = "0644";
    };
  };
}
