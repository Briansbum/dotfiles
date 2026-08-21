# grocy VM — household management (php-fpm + nginx).
# State: /data/grocy (sqlite db + uploads) via 9p.
{
  inputs,
}:
import ./mk-service-vm.nix {
  inherit inputs;
  name = "grocy";
  modules = [
    (
      { lib, ... }:
      {
        users.users.grocy.uid = 310;
        users.groups.grocy.gid = 310;

        services.grocy = {
          enable = true;
          hostName = "grocy.koch.brians.skin";
          nginx.enableSSL = false;
          dataDir = "/data/grocy/data";
          settings = {
            currency = "GBP";
            culture = "en_GB";
            calendar.firstDayOfWeek = 1; # Monday
          };
        };

        # Keep the same on-guest port layout as before: nginx on 2383
        services.nginx.virtualHosts."grocy.koch.brians.skin".listen = [
          {
            addr = "0.0.0.0";
            port = 2383;
          }
        ];

        koch-vm = {
          memory = 512;
          ports = [
            { guestPort = 2383; } # -> 127.0.0.1:2383, Traefik fronts this
          ];
        };

        virtualisation.sharedDirectories.grocy = {
          source = "/data/grocy";
          target = "/data/grocy";
          securityModel = "none";
        };

        systemd.tmpfiles.rules = [
          "d /data/grocy/data 0750 grocy nginx -"
        ];
      }
    )
  ];
}
