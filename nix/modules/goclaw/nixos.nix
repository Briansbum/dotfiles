# GoClaw NixOS implementation — Docker container, NixOS PostgreSQL, nginx.
#
# The container image is built by Nix (loaded at service start via docker load)
# but is NOT a Nix-closure image. The image is a minimal scratch-based OCI image:
#   - goclaw static binary at /usr/local/bin/goclaw
#   - migrations + skills copied to /usr/local/share/goclaw/
#   - NO Nix store baked in
#
# Heavy runtime deps (chromium, claude-code, skill binaries) come from the HOST
# via /nix/store:ro mount. Nix-store paths in env vars work transparently because
# the entire store is visible inside the container.
#
# PostgreSQL auth is trust on local socket — peer auth requires matching OS uid,
# which doesn't hold for a container process.

{ config, pkgs, lib, ... }:

let
  cfg = config.services.goclaw;

  secretNames = lib.unique (lib.attrValues cfg.secretEnvironment);

  # Minimal OCI image: static goclaw binary + data at standard paths.
  # /nix/store is mounted at runtime so all Nix-path env vars still resolve.
  goclawImage = pkgs.dockerTools.buildLayeredImage {
    name = "goclaw";
    tag = "latest";

    fakeRootCommands = ''
      mkdir -p /usr/local/bin \
               /usr/local/share/goclaw \
               /tmp /var/log /etc /data

      # Static Go binary — no shared-lib deps, runs on any Linux kernel
      cp ${cfg.package}/bin/goclaw /usr/local/bin/goclaw
      chmod 755 /usr/local/bin/goclaw

      # Migrations and bundled skills at standard paths
      cp -r ${cfg.package}/share/goclaw/migrations /usr/local/share/goclaw/
      cp -r ${cfg.package}/share/goclaw/skills     /usr/local/share/goclaw/

      # Minimal /etc for Go's net and user-lookup packages
      printf 'root:x:0:0:root:/:/bin/false\nnobody:x:65534:65534:nobody:/:/bin/false\n' \
        > /etc/passwd
      printf 'root:x:0:\nnobody:x:65534:\n' > /etc/group
      printf 'hosts: files dns\n' > /etc/nsswitch.conf

      chmod 1777 /tmp
    '';
    enableFakechroot = true;

    config = {
      Entrypoint = [ "/usr/local/bin/goclaw" ];
      Cmd = [ ];
      WorkingDir = cfg.stateDir;
      # /nix/store is mounted at runtime; cacert path resolves via that mount.
      Env = [
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
    };
  };

  # Override _commonEnv paths that were pointing into the Nix store for the
  # binary itself; data files are now at standard paths inside the image.
  # All OTHER Nix-store paths (claude-code, chromium, skill binaries) stay as-is
  # because /nix/store is mounted read-only into the container.
  containerEnv = cfg._commonEnv // {
    GOCLAW_MIGRATIONS_DIR    = "/usr/local/share/goclaw/migrations";
    GOCLAW_BUNDLED_SKILLS_DIR = "/usr/local/share/goclaw/skills";
  };

  # Writes secrets to /run/goclaw/env. Docker reads this from HOST before start.
  prepareEnv = pkgs.writeShellScript "goclaw-prepare-env" ''
    set -euo pipefail
    umask 077
    {
      ${lib.concatStringsSep "\n      " (lib.mapAttrsToList (envVar: secretName:
        "printf '${envVar}=%s\\n' \"$(cat ${config.sops.secrets.${secretName}.path})\""
      ) cfg.secretEnvironment)}
    } > /run/goclaw/env
  '';
in
{
  imports = [ ./default.nix ];

  config = lib.mkIf cfg.enable {
    # -----------------------------------------------------------------------
    # sops secrets — root-readable; Docker reads env file from host path
    # -----------------------------------------------------------------------

    sops.secrets = lib.listToAttrs (map (name: {
      inherit name;
      value = {
        owner = "root";
        group = cfg.group;
        mode = "0440";
        restartUnits = [ "goclaw-prepare.service" ];
      };
    }) secretNames);

    # -----------------------------------------------------------------------
    # System user — still needed for stateDir ownership
    # -----------------------------------------------------------------------

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
    };
    users.groups.${cfg.group} = {};

    # -----------------------------------------------------------------------
    # PostgreSQL — trust on local socket (peer won't work from container)
    # -----------------------------------------------------------------------

    services.postgresql.ensureDatabases = [ "goclaw" ];
    services.postgresql.ensureUsers = [{
      name = cfg.user;
      ensureDBOwnership = true;
    }];
    services.postgresql.authentication = lib.mkAfter ''
      local goclaw ${cfg.user} trust
    '';

    # -----------------------------------------------------------------------
    # Docker daemon
    # -----------------------------------------------------------------------

    virtualisation.docker.enable = true;

    # -----------------------------------------------------------------------
    # Pre-start oneshot: DB extensions, state dirs, env file
    # -----------------------------------------------------------------------

    systemd.services.goclaw-prepare = {
      description = "GoClaw pre-start preparation";
      wantedBy = [ "multi-user.target" ];
      after    = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      before   = [ "${config.virtualisation.oci-containers.backend}-goclaw.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Creates /run/goclaw; env file lives here, read by Docker at start.
        RuntimeDirectory     = "goclaw";
        RuntimeDirectoryMode = "0750";

        ExecStart = pkgs.writeShellScript "goclaw-prepare" ''
          set -euo pipefail

          ${pkgs.util-linux}/bin/runuser -u postgres -- \
            ${config.services.postgresql.package}/bin/psql -d goclaw \
            -c 'CREATE EXTENSION IF NOT EXISTS "pgcrypto";'
          ${pkgs.util-linux}/bin/runuser -u postgres -- \
            ${config.services.postgresql.package}/bin/psql -d goclaw \
            -c 'CREATE EXTENSION IF NOT EXISTS "vector";'

          ${cfg._prepareState}
          ${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.group} ${cfg.stateDir}

          ${prepareEnv}
        '';
      };
    };

    # Container must start after prepare (creates the env file Docker needs)
    systemd.services."${config.virtualisation.oci-containers.backend}-goclaw" = {
      after    = [ "goclaw-prepare.service" ];
      requires = [ "goclaw-prepare.service" ];
    };

    # -----------------------------------------------------------------------
    # OCI container
    # -----------------------------------------------------------------------

    virtualisation.oci-containers.backend = lib.mkDefault "docker";
    virtualisation.oci-containers.containers.goclaw = {
      image     = "goclaw:latest";
      imageFile = goclawImage;   # Nix builds the image; systemd loads it

      environment     = containerEnv;
      environmentFiles = [ "/run/goclaw/env" ];  # Docker reads from host

      volumes = [
        "${cfg.stateDir}:${cfg.stateDir}:rw"
        "${cfg.logsDir}:${cfg.logsDir}:rw"
        "/run/postgresql:/run/postgresql"   # PostgreSQL Unix socket
        "/nix/store:/nix/store:ro"          # chromium, claude-code, skill bins
      ] ++ cfg.extraContainerVolumes;

      extraOptions = [
        "--network=host"    # goclaw listens on host loopback; nginx proxies to it
        "--shm-size=256m"   # Chromium uses /dev/shm for V8 JIT
      ];

      workdir = cfg.stateDir;
    };

    # -----------------------------------------------------------------------
    # Web UI — nginx virtual host (fronted by Traefik in host config)
    # -----------------------------------------------------------------------

    services.nginx.enable = lib.mkDefault true;
    services.nginx.virtualHosts.${cfg.webUi.hostName} = lib.mkIf cfg.webUi.enable {
      listen = [{ addr = "127.0.0.1"; port = cfg.uiPort; }];
      root   = "${cfg.uiPackage}/share/goclaw-ui";

      locations."/" = {
        tryFiles = "$uri $uri/ /index.html";
      };

      locations."/assets/" = {
        extraConfig = ''
          expires 1y;
          add_header Cache-Control "public, immutable";
        '';
      };

      locations."/ws" = {
        proxyPass       = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
      };

      locations."/v1/"    = { proxyPass = "http://127.0.0.1:${toString cfg.port}"; };
      locations."/health" = { proxyPass = "http://127.0.0.1:${toString cfg.port}"; };
    };
  };
}
