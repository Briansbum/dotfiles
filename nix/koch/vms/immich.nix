# immich VM — photo management (server + machine-learning + postgres).
# Heaviest guest (4G RAM for ML). State:
#   - /data/photos/immich (library + postgres data dir lives under it on the
#     old setup; here postgresql dataDir is pointed into the share too)
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
      {
        users.users.immich.uid = 996;
        users.users.immich.group = "immich";
        users.groups.immich.gid = 997;

        services.immich = {
          enable = true;
          port = 2283;
          mediaLocation = "/data/photos/immich";
          machine-learning.enable = true;
        };

        # DB dumps still happen on the host against this share
        services.postgresql.dataDir = lib.mkForce "/data/photos/immich/postgresql";

        koch-vm = {
          memory = 4096;
          vcpus = 4; # ML is CPU-hungry; don't let it eat all of koch
          ports = [
            { guestPort = 2283; } # -> 127.0.0.1:2283, Traefik fronts this
          ];
        };

        # securityModel "none": qemu runs unprivileged as alex on the host;
        # guest uids are chosen to match host uids (immich=996) so 9p just works.
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

        # Daily DB dump (moved from the koch host — postgres runs here now).
        # Lands on /data/photos/immich/db-backup via the 9p share so the
        # host's B2 backup picks it up unchanged.
        systemd.services.immich-db-dump = {
          description = "Dump Immich PostgreSQL database for backup";
          after = [ "postgresql.service" ];
          requires = [ "postgresql.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            ExecStart = with pkgs; writeShellScript "immich-db-dump" ''
              mkdir -p /data/photos/immich/db-backup
              chmod 762 /data/photos/immich/db-backup || true
              ${config.services.postgresql.package}/bin/pg_dump immich | ${gzip}/bin/gzip > /data/photos/immich/db-backup/immich-dump.sql.gz
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
