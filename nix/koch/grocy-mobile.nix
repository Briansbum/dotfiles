# grocy-mobile on koch — thin Go frontend for Grocy tasks & chores.
#
# Runs as a plain systemd service (single static binary, no container needed).
# Grocy API key is injected via sops EnvironmentFile.
#
# Pre-deploy checklist:
#   1. Add grocy_mobile_api_key to nix/koch/secrets.yaml via sops

{ config, pkgs, ... }:

{
  sops.secrets.grocy_mobile_api_key = {
    owner        = "grocy-mobile";
    mode         = "0400";
    restartUnits = [ "grocy-mobile.service" ];
  };

  users.users.grocy-mobile = {
    isSystemUser = true;
    group        = "grocy-mobile";
  };
  users.groups.grocy-mobile = {};

  systemd.services.grocy-mobile = {
    description = "grocy-mobile — mobile Grocy frontend";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network.target" ];

    environment = {
      GROCY_BASE_URL = "http://127.0.0.1:2383";
      LISTEN_ADDR    = "127.0.0.1:8090";
    };

    serviceConfig = {
      ExecStart        = "${pkgs.grocy-mobile}/bin/grocy-mobile";
      EnvironmentFile  = config.sops.secrets.grocy_mobile_api_key.path;
      User             = "grocy-mobile";
      Group            = "grocy-mobile";
      Restart          = "on-failure";
      RestartSec       = "5s";
      # Hardening
      NoNewPrivileges  = true;
      PrivateTmp       = true;
      ProtectSystem    = "strict";
      ProtectHome      = true;
    };
  };

  # Traefik router
  services.traefik.dynamicConfigOptions.http.routers.grocy-mobile = {
    rule             = "Host(`tasks.koch.brians.skin`)";
    service          = "grocy-mobile";
    tls.certResolver = "desec";
  };
  services.traefik.dynamicConfigOptions.http.services.grocy-mobile.loadBalancer.servers = [
    { url = "http://127.0.0.1:8090"; }
  ];
}
