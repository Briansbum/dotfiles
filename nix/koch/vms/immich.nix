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
        # virtiofsd runs as host alex (uid 1000, gid users/100). Keep Immich's
        # service and primary group aligned so share file creation can set its gid.
        services.immich = {
          enable = true;
          group = lib.mkForce "users";
          host = "";
          port = 2283;
          mediaLocation = "/data/photos/immich";
          machine-learning = {
            enable = true;
            # Keep the worker count explicit: a model load can otherwise
            # coincide with several concurrent jobs and exhaust this guest.
            environment.MACHINE_LEARNING_WORKERS = "1";
          };
        };

        koch-vm = {
          monitoring.partials = [ ./monitoring/immich.alloy ];
          # The ML service has recorded repeated guest OOM kills.  Leave
          # enough headroom for the model plus PostgreSQL and Immich server.
          memory = 6144;
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
          # Immich writes derivatives and uploads into this share.
          # virtiofs provides the page cache without the old 9p msize tuning.
          sharedDirectories.photos = {
            source = "/data/photos";
            target = "/data/photos";
            writable = true;
          };
          sharedDirectories.immich-secrets = {
            source = "/var/lib/koch-vm/immich";
            target = "/mnt/immich-secrets";
          };
        };

        # virtiofs caching is configured by the host-side daemon; do not add
        # 9p-only mount options such as cache=loose to the guest filesystem.

        # NOTE: inotify does not cross 9p (nor virtiofs). Immich's per-library
        # "watch" toggle must stay OFF; external libraries are picked up by
        # their scheduled scan instead. Configure in the Immich UI per library.

        systemd.tmpfiles.rules = [
          "d /data/photos/immich 0750 immich users -"
        ];

        # Restores from the dump the previous setup left in db-backup/. Runs as
        # postgres because the dump (pg_dump --clean) recreates extensions and
        # schemas, which needs superuser. The dump was taken while the old
        # install still had pgvecto.rs around, so its vestigial empty "vectors"
        # schema/extension is stripped: the extension no longer exists in
        # nixpkgs and those statements would abort an ON_ERROR_STOP restore.
        systemd.services.immich-db-restore = {
          description = "Restore the Immich database from the dump on the share";
          after = [ "postgresql.target" ];
          requires = [ "postgresql.target" ];
          unitConfig.ConditionPathExists = "!/var/lib/immich-restore/done";
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            StateDirectory = "immich-restore";
            ExecStart = pkgs.writeShellScript "immich-db-restore" ''
              set -euo pipefail
              if [ -e ${dump} ]; then
                # Finish decompression before psql can commit: pipefail alone
                # cannot undo a transaction committed after a truncated input.
                restoreSql=$(mktemp)
                trap 'rm -f "$restoreSql"' EXIT
                ${pkgs.gzip}/bin/gunzip -c ${dump} \
                  | grep -vE '^(CREATE EXTENSION IF NOT EXISTS vectors|CREATE SCHEMA vectors|ALTER SCHEMA vectors|GRANT SELECT ON TABLE vectors\.|COMMENT ON EXTENSION vectors)' \
                  > "$restoreSql"
                ${pgBin}/psql --no-psqlrc --single-transaction -v ON_ERROR_STOP=1 -d immich -f "$restoreSql"
              else
                echo "ERROR: no dump at ${dump}; refusing to mark the database restored" >&2
                exit 1
              fi
              touch /var/lib/immich-restore/done
            '';
          };
        };
        systemd.services.immich-server = {
          after = [ "immich-db-restore.service" ];
          requires = [ "immich-db-restore.service" ];
        };

        # Daily dump. Depends on immich-db-restore so a fresh/blank database
        # can never overwrite a good dump on the share (restore is a oneshot
        # gated on the done marker; a skipped condition counts as success,
        # so this ordering is safe across reboots).
        systemd.services.immich-db-dump = {
          description = "Dump Immich PostgreSQL database for backup";
          after = [
            "postgresql.target"
            "immich-db-restore.service"
          ];
          requires = [
            "postgresql.target"
            "immich-db-restore.service"
          ];
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
