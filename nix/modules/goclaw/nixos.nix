# GoClaw NixOS implementation — Docker container, NixOS PostgreSQL, nginx.
#
# The container image is a self-contained layered OCI image built by Nix.
# All runtime deps (goclaw binary, chromium, claude-code, shell tools) are
# baked into image layers via `contents` — no /nix/store bind-mount needed.
#
# The container runs as a pinned non-root goclaw user (uid/gid from cfg).
# The host system user uses the same uid/gid so bind-mounted volume ownership
# is consistent without any runtime chown.
#
# PostgreSQL auth is trust on local socket — peer auth requires matching OS uid,
# which doesn't hold for a container process.

{ config, pkgs, lib, ... }:

let
  cfg = config.services.goclaw;

  secretNames = lib.unique (lib.attrValues cfg.secretEnvironment);

  # Named bridge network shared by goclaw and chrome sidecar containers.
  # Replaces --network=host; containers communicate via Docker DNS (container name).
  networkName = "goclaw";

  # Self-contained OCI image: all runtime closures baked into image layers.
  # No /nix/store bind-mount needed — contents embeds the full dependency graph.
  goclawImage = pkgs.dockerTools.buildLayeredImage {
    name = "goclaw";
    tag = "latest";

    contents = [
      cfg.package          # goclaw binary, migrations, bundled skills
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.cacert
      pkgs.claude-code
      # chromium is intentionally absent: use the browser.sidecar option instead.
      # Chrome cannot sandbox itself when running as non-root without SYS_ADMIN;
      # the sidecar runs Chrome with --no-sandbox in its own container.
    ];

    fakeRootCommands = ''
      # goclaw user/group — uid/gid are pinned to match the host system user
      # so bind-mounted stateDir ownership is consistent without runtime chown.
      printf 'root:x:0:0:root:/root:/bin/sh\ngoclaw:x:${toString cfg.uid}:${toString cfg.gid}:goclaw:${cfg.stateDir}:/bin/bash\nnobody:x:65534:65534:nobody:/:/bin/false\n' \
        > /etc/passwd
      printf 'root:x:0:\ngoclaw:x:${toString cfg.gid}:\nnobody:x:65534:\n' > /etc/group
      printf 'hosts: files dns\n' > /etc/nsswitch.conf

      # State and log dirs must exist in the image so Docker can set WorkingDir
      # and create the bind-mount targets before the volumes are attached.
      mkdir -p ${cfg.stateDir} ${cfg.logsDir} /tmp /run
      chmod 1777 /tmp
    '';
    enableFakechroot = true;

    config = {
      Entrypoint = [ "${cfg.package}/bin/goclaw" ];
      Cmd = [ ];
      WorkingDir = cfg.stateDir;
      User = "${toString cfg.uid}:${toString cfg.gid}";
      Env = [
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "HOME=${cfg.stateDir}"
      ];
    };
  };

  # All Nix store paths in _commonEnv exist inside the image via contents.
  # When the Chrome sidecar is enabled, point goclaw at it via CDP so the
  # local launcher (which requires --no-sandbox for non-root) is never used.
  containerEnv = cfg._commonEnv
    // lib.optionalAttrs cfg.browser.sidecar.enable {
      GOCLAW_BROWSER_REMOTE_URL = "ws://chrome:${toString cfg.browser.sidecar.port}";
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
      uid = cfg.uid;
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
    };
    users.groups.${cfg.group} = { gid = cfg.gid; };

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

    # Bridge network — must exist before either container starts.
    systemd.services.goclaw-network = {
      description = "Create goclaw Docker bridge network";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "docker.service" "docker.socket" ];
      requires    = [ "docker.service" ];
      before      = [
        "${config.virtualisation.oci-containers.backend}-goclaw.service"
        "${config.virtualisation.oci-containers.backend}-chrome.service"
      ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "goclaw-network-create" ''
          set -euo pipefail
          ${pkgs.docker}/bin/docker network inspect ${networkName} >/dev/null 2>&1 || \
            ${pkgs.docker}/bin/docker network create --driver bridge ${networkName}
        '';
        ExecStop = pkgs.writeShellScript "goclaw-network-rm" ''
          ${pkgs.docker}/bin/docker network rm ${networkName} 2>/dev/null || true
        '';
      };
    };

    # Container must start after prepare (creates the env file Docker needs) and after network.
    systemd.services."${config.virtualisation.oci-containers.backend}-goclaw" = {
      after    = [ "goclaw-prepare.service" "goclaw-network.service" ];
      requires = [ "goclaw-prepare.service" "goclaw-network.service" ];
    };

    systemd.services."${config.virtualisation.oci-containers.backend}-chrome" = lib.mkIf cfg.browser.sidecar.enable {
      after    = [ "goclaw-network.service" ];
      requires = [ "goclaw-network.service" ];
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
      ] ++ cfg.extraContainerVolumes;

      extraOptions = [
        "--network=${networkName}"
        "--publish=127.0.0.1:${toString cfg.port}:${toString cfg.port}"
        "--shm-size=256m"
      ];

      workdir = cfg.stateDir;
    };

    # -----------------------------------------------------------------------
    # Chrome sidecar — headless Chrome reachable via CDP on localhost.
    # goclaw connects to it via GOCLAW_BROWSER_REMOTE_URL instead of
    # launching Chrome locally (which requires --no-sandbox for non-root).
    # The sidecar image runs Chrome with --no-sandbox itself; Docker provides
    # the outer isolation layer.
    # -----------------------------------------------------------------------

    virtualisation.oci-containers.containers.chrome = lib.mkIf cfg.browser.sidecar.enable {
      image = cfg.browser.sidecar.image;

      cmd = [
        "--no-sandbox"
        "--remote-debugging-address=0.0.0.0"
        "--remote-debugging-port=${toString cfg.browser.sidecar.port}"
        "--remote-allow-origins=*"
        "--disable-gpu"
        "--disable-dev-shm-usage"
      ];

      extraOptions = [
        "--network=${networkName}"
        "--shm-size=2g"
      ];
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
