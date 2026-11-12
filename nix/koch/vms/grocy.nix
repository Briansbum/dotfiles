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
      { config, lib, pkgs, ... }:
      {
        users.users.grocy.uid = 1000;

        # Rootless virtiofsd can only create files as host alex:users (1000:100).
        # The upstream nginx group makes cache writes fail with EPERM, so Grocy
        # can never persist its version marker and redirects to / forever.
        # Keep the FPM socket owned by nginx; only change the worker's group.
        services.phpfpm.pools.grocy.group = lib.mkForce "users";

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

        # SIGQUIT asks the FPM master to stop accepting connections and drain
        # existing requests. Only signal the master; it coordinates its workers.
        systemd.services.phpfpm-grocy.serviceConfig = {
          KillSignal = "SIGQUIT";
          KillMode = "mixed";
          TimeoutStopSec = "5min";
        };

        # The application produces recoverable material; the host only ships it.
        systemd.services.grocy-backup = lib.mkIf config.koch-vm.backup.enable {
          description = "Stage a consistent Grocy database, uploads and configuration archive";
          # Do not depend/order on the pool itself: this service stops it,
          # and a dependency would risk stop propagation or job-order cycles.
          after = [ "grocy-setup.service" ];
          unitConfig.RequiresMountsFor = [ config.koch-vm.backup.directory ];
          serviceConfig = {
            Type = "oneshot";
            # A stalled filesystem or SQLite operation must not keep Grocy down.
            TimeoutStartSec = "30min";
            UMask = "0077";
            # Even if the producer fails/times out, restore application service.
            ExecStopPost = "${pkgs.systemd}/bin/systemctl --no-block start phpfpm-grocy.service";
          };
          script = ''
            set -euo pipefail
            # Gracefully drain PHP requests before capturing files and SQLite.
            ${pkgs.systemd}/bin/systemctl stop phpfpm-grocy.service
            # Do not publish a snapshot if systemd had to kill stuck workers.
            test "$(${pkgs.systemd}/bin/systemctl show -p Result --value phpfpm-grocy.service)" = success
            # Match virtiofsd's host UID/GID when creating staged files.
            ${pkgs.util-linux}/bin/runuser -u grocy -g users -- \
              ${pkgs.python3}/bin/python3 ${./grocy-backup.py} \
              ${lib.escapeShellArg config.services.grocy.dataDir} \
              ${lib.escapeShellArg config.koch-vm.backup.directory} \
              /etc/grocy/config.php
          '';
        };
        systemd.timers.grocy-backup = lib.mkIf config.koch-vm.backup.enable {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 02:30:00";
            Persistent = true;
          };
        };

        # Keep the same on-guest port layout as before: nginx on 2383
        services.nginx.virtualHosts."grocy.koch.brians.skin" = {
          listen = [
            {
              addr = "0.0.0.0";
              port = 2383;
            }
          ];
          # Traefik terminates TLS before forwarding to this guest.  PHP must
          # see the original request as HTTPS or Grocy keeps redirecting the
          # already-HTTPS public URL back to itself.
          locations."~ \\.php$".extraConfig = lib.mkAfter ''
            fastcgi_param HTTPS on;
          '';
        };

        koch-vm = {
          backup.requiredMounts = [ "/data" ];
          monitoring.partials = [ ./monitoring/grocy.alloy ];
          memory = 512;
          ports = [
            { guestPort = 2383; } # -> 127.0.0.1:2383, Traefik fronts this
          ];
        };

        virtualisation.sharedDirectories.grocy = {
          source = "/data/grocy";
          target = "/data/grocy";
          writable = true;
        };

        systemd.tmpfiles.rules = [
          "d /data/grocy/data 0750 grocy nginx -"
        ];
      }
    )
  ];
}
