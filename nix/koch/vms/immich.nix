# immich VM — photo management (server + machine-learning + postgres).
# Heaviest guest (4G RAM for ML). State:
#   - /data/photos/immich (library) via 9p; postgres lives on the guest disk
#     and a daily dump lands on the share for the host's B2 backup
#   - external photo dirs shared read-only-ish (9p rw for v1, tighten later)
{
  inputs,
}:
import ./mk-service-vm.nix {
  inherit inputs;
  name = "immich";
  modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        dumpDir = "/data/photos/immich/db-backup";
        dump = "${dumpDir}/immich-dump.sql.gz";
        pgBin = "${config.services.postgresql.package}/bin";
      in
      {
        users.users.immich.uid = 1000;
        users.users.immich.group = "immich";

        services.immich = {
          enable = true;
          host = "";
          port = 2283;
          mediaLocation = "/data/photos/immich";
          machine-learning.enable = true;
        };

        koch-vm = {
          memory = 4096;
          vcpus = 4; # ML is CPU-hungry; don't let it eat all of koch
          diskSize = 16384;
          ports = [
            { guestPort = 2283; } # -> 127.0.0.1:2283, Traefik fronts this
            { guestPort = 5432; } # -> 127.0.0.1:5432, host Alloy scrapes postgres
          ];
        };

        services.postgresql = {
          enableTCPIP = true;
          authentication = "host immich alloy 10.0.2.2/32 scram-sha-256";
          ensureUsers = [ { name = "alloy"; } ];
        };
        systemd.services.immich-alloy-role = {
          description = "Set the alloy monitoring role's password and grants";
          after = [ "postgresql.target" ];
          requires = [ "postgresql.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            LoadCredential = [ "pw:/mnt/immich-secrets/alloy-pg-password" ];
            ExecStart = pkgs.writeShellScript "immich-alloy-role" ''
              set -euo pipefail
              ${pgBin}/psql -v ON_ERROR_STOP=1 -v pw="$(cat "$CREDENTIALS_DIRECTORY/pw")" <<'SQL'
              ALTER ROLE alloy WITH LOGIN PASSWORD :'pw';
              GRANT pg_monitor TO alloy;
              SQL
            '';
          };
        };

        virtualisation = {
          # Photo archive is read-mostly and scanned on a schedule: give the
          # guest a real page cache instead of a vmexit round-trip per read.
          # Coherency tradeoff is fine — the host doesn't mutate photos.
          msize = 1048576; # 1M — full-res reads for thumb/ML jobs in fat chunks
          sharedDirectories.photos = {
            source = "/data/photos";
            target = "/data/photos";
            securityModel = "none";
          };
          sharedDirectories.immich-secrets = {
            source = "/var/lib/koch-vm/immich";
            target = "/mnt/immich-secrets";
          };
        };

        # qemu-vm.nix only sets cache= for the nix-store share, and its
        # mkVMOverride on fileSystems swallows plain fileSystems defs — so
        # set it at the source here.
        virtualisation.fileSystems."/data/photos".options = [ "cache=loose" ];

        # NOTE: inotify does not cross 9p (nor virtiofs). Immich's per-library
        # "watch" toggle must stay OFF; external libraries are picked up by
        # their scheduled scan instead. Configure in the Immich UI per library.

        systemd.tmpfiles.rules = [
          "d /data/photos/immich 0750 immich immich -"
        ];

        systemd.services.immich-db-restore = {
          description = "Restore the Immich database from the dump on the share";
          after = [ "postgresql.target" ];
          requires = [ "postgresql.target" ];
          unitConfig.ConditionPathExists = "!/var/lib/immich-restore/done";
          serviceConfig = {
            Type = "oneshot";
            User = "immich";
            StateDirectory = "immich-restore";
            ExecStart = pkgs.writeShellScript "immich-db-restore" ''
              set -euo pipefail
              if [ -e ${dump} ]; then
                ${pkgs.gzip}/bin/gunzip -c ${dump} | ${pgBin}/psql -d immich
              fi
              touch /var/lib/immich-restore/done
            '';
          };
        };
        systemd.services.immich-server = {
          after = [ "immich-db-restore.service" ];
          requires = [ "immich-db-restore.service" ];
        };

        systemd.services.immich-db-dump = {
          description = "Dump Immich PostgreSQL database for backup";
          after = [ "postgresql.target" ];
          requires = [ "postgresql.target" ];
          serviceConfig = {
            Type = "oneshot";
            User = "immich";
            ExecStart = pkgs.writeShellScript "immich-db-dump" ''
              set -euo pipefail
              mkdir -p ${dumpDir}
              ${pgBin}/pg_dump immich | ${pkgs.gzip}/bin/gzip > ${dump}.tmp
              mv ${dump}.tmp ${dump}
            '';
          };
        };
        systemd.timers.immich-db-dump = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };
      }
    )
  ];
}
