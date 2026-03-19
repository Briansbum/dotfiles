# GoClaw darwin implementation — runs goclaw itself inside an Apple Container.
#
# The container is a minimal OCI image built by Nix:
#   - goclaw Linux/aarch64 binary (cross-compiled from aarch64-darwin)
#   - claude-code Linux/aarch64 binary
#   - NO Nix store baked in
#
# PostgreSQL stays on the host (Homebrew). The container reaches it via the
# Unix socket, mounted in from /private/tmp (Homebrew PG default socket dir).
#
# The docker-to-container shim is still present so goclaw can spawn agent
# sandbox sub-containers from inside the container (requires the host's
# Apple Container CLI to be available via a bind-mount).

{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.services.goclaw;

  secretNames = lib.unique (lib.attrValues cfg.secretEnvironment);

  # Homebrew PostgreSQL paths (Apple Silicon)
  pgBin = "/opt/homebrew/opt/postgresql@17/bin";

  pgRole     = "goclaw";
  pgDatabase = "goclaw";

  # -----------------------------------------------------------------------
  # Cross-compiled Linux/aarch64 packages (Apple Container runs Linux VMs)
  # -----------------------------------------------------------------------

  # pkgsCross.aarch64-linux: same arch as host (aarch64) but Linux OS.
  # CGO_ENABLED=0 Go binaries cross-compile cleanly: GOOS=linux GOARCH=arm64.
  lp = pkgs.pkgsCross.aarch64-multiplatform;

  goclawLinux      = lp.goclaw;
  claudeCodeLinux  = inputs.claude-code.packages.aarch64-linux.default;

  # Minimal OCI image for Apple Container (Linux/aarch64).
  # Same philosophy as nixos.nix: static binary at standard path, no Nix store.
  # On macOS we CAN'T mount /nix/store (Darwin binaries ≠ Linux), so
  # claude-code is baked into the image directly.
  goclawImage = pkgs.dockerTools.buildLayeredImage {
    name = "goclaw";
    tag  = "latest";

    fakeRootCommands = ''
      mkdir -p /usr/local/bin \
               /usr/local/share/goclaw \
               /tmp /var/log /etc /data

      # goclaw — static Linux/aarch64 binary
      cp ${goclawLinux}/bin/goclaw /usr/local/bin/goclaw
      chmod 755 /usr/local/bin/goclaw

      # claude-code Linux binary (baked in because macOS /nix/store has Darwin bins)
      cp ${claudeCodeLinux}/bin/claude /usr/local/bin/claude
      chmod 755 /usr/local/bin/claude

      # Migrations and bundled skills
      cp -r ${goclawLinux}/share/goclaw/migrations /usr/local/share/goclaw/
      cp -r ${goclawLinux}/share/goclaw/skills     /usr/local/share/goclaw/

      # CA certificates (baked in since macOS /nix/store has Darwin bundles)
      mkdir -p /etc/ssl/certs
      cp ${lp.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt

      # Minimal /etc for Go net/user packages
      printf 'root:x:0:0:root:/:/bin/false\nnobody:x:65534:65534:nobody:/:/bin/false\n' \
        > /etc/passwd
      printf 'root:x:0:\nnobody:x:65534:\n' > /etc/group
      printf 'hosts: files dns\n' > /etc/nsswitch.conf

      chmod 1777 /tmp
    '';

    config = {
      Cmd      = [ "/usr/local/bin/goclaw" ];
      WorkingDir = cfg.stateDir;
      Env = [
        # TLS certs from the baked-in cacert closure via nix store...
        # For macOS we include cacert in the image since we can't mount store.
        "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
      ];
    };
  };

  # -----------------------------------------------------------------------
  # Container-specific env
  # -----------------------------------------------------------------------
  # _commonEnv uses Darwin package paths — override the ones that differ.

  containerEnv = {
    GOCLAW_HOST               = "127.0.0.1";
    GOCLAW_PORT               = toString cfg.port;
    GOCLAW_DATA_DIR           = cfg.stateDir;
    GOCLAW_CONFIG             = "${cfg.stateDir}/config/goclaw.json";
    GOCLAW_WORKSPACE          = "${cfg.stateDir}/workspace";
    GOCLAW_MIGRATIONS_DIR     = "/usr/local/share/goclaw/migrations";
    GOCLAW_BUNDLED_SKILLS_DIR = "/usr/local/share/goclaw/skills";
    GOCLAW_SKILLS_DIR         = "${cfg.stateDir}/workspace/skills";
    GOCLAW_AUTO_UPGRADE       = "true";
    GOCLAW_TELEMETRY_ENABLED  = "false";
    GOCLAW_POSTGRES_DSN       = cfg.postgresDSN;
    GOCLAW_CLAUDE_CLI_PATH    = "/usr/local/bin/claude";
    GOCLAW_CLAUDE_CLI_WORK_DIR = "${cfg.stateDir}/workspace";
  } // (lib.optionalAttrs cfg.sandbox.enable {
    GOCLAW_SANDBOX_MODE             = cfg.sandbox.mode;
    GOCLAW_SANDBOX_IMAGE            = cfg.sandbox.image;
    GOCLAW_SANDBOX_MEMORY_MB        = toString cfg.sandbox.memoryMB;
    GOCLAW_SANDBOX_CPUS             = lib.strings.floatToString cfg.sandbox.cpus;
    GOCLAW_SANDBOX_SCOPE            = cfg.sandbox.scope;
    GOCLAW_SANDBOX_WORKSPACE_ACCESS = cfg.sandbox.workspaceAccess;
    GOCLAW_SANDBOX_NETWORK          = "false";
  }) // cfg.environment;

  # -----------------------------------------------------------------------
  # DB bootstrap (runs as alex, the Homebrew PG superuser)
  # -----------------------------------------------------------------------

  pgInitScript = pkgs.writeShellScript "goclaw-pg-init" ''
    set -euo pipefail
    PSQL="${pgBin}/psql"
    CREATEUSER="${pgBin}/createuser"
    CREATEDB="${pgBin}/createdb"

    if ! "$PSQL" -h localhost -c '\q' postgres 2>/dev/null; then
      echo "goclaw-pg-init: PostgreSQL not reachable, skipping"
      exit 0
    fi

    if ! "$PSQL" -h localhost -tAc "SELECT 1 FROM pg_roles WHERE rolname='${pgRole}'" postgres | grep -q 1; then
      echo "goclaw-pg-init: creating role '${pgRole}'"
      "$CREATEUSER" -h localhost --no-superuser --no-createdb --no-createrole "${pgRole}"
    fi

    if ! "$PSQL" -h localhost -tAc "SELECT 1 FROM pg_database WHERE datname='${pgDatabase}'" postgres | grep -q 1; then
      echo "goclaw-pg-init: creating database '${pgDatabase}'"
      "$CREATEDB" -h localhost --owner="${pgRole}" "${pgDatabase}"
    fi

    "$PSQL" -h localhost -d "${pgDatabase}" -c 'CREATE EXTENSION IF NOT EXISTS "pgcrypto";' 2>/dev/null || true
    "$PSQL" -h localhost -d "${pgDatabase}" -c 'CREATE EXTENSION IF NOT EXISTS "vector";' 2>/dev/null || \
      echo "goclaw-pg-init: pgvector not available (brew install pgvector)"
  '';

  # -----------------------------------------------------------------------
  # docker→container shim (for agent sandbox sub-containers spawned by goclaw)
  # -----------------------------------------------------------------------

  dockerShim = pkgs.writeShellScriptBin "docker" (builtins.readFile ./docker-to-container-shim.sh);

  # -----------------------------------------------------------------------
  # Wrapper — bootstraps everything, loads image, runs container
  # -----------------------------------------------------------------------

  # Stamp file: we only rebuild the image when the goclaw Nix store path changes.
  imageStampPath = "${cfg.stateDir}/.container-image-hash";

  goclawWrapper = pkgs.writeShellScript "goclaw-wrapper" ''
    set -euo pipefail
    CONTAINER_CLI="/usr/local/bin/container"

    # DB init runs as alex (Homebrew PG superuser)
    /usr/bin/sudo -u alex ${pgInitScript}

    # Prepare state directories (runs as root, chown handled inside)
    ${cfg._prepareState}

    # Ensure Apple Container system is running
    if ! "$CONTAINER_CLI" system status >/dev/null 2>&1; then
      echo "goclaw: starting Apple Container system..."
      "$CONTAINER_CLI" system start
      sleep 3
    fi

    # Load the Nix-built image only when it has changed (stamp = Nix store path)
    EXPECTED="${goclawImage}"
    if [ "$(cat "${imageStampPath}" 2>/dev/null)" != "$EXPECTED" ]; then
      echo "goclaw: loading container image..."
      "$CONTAINER_CLI" image load --input "${goclawImage}"
      echo "$EXPECTED" > "${imageStampPath}"
    fi

    # Remove any stale container from a previous run
    "$CONTAINER_CLI" rm -f goclaw-main 2>/dev/null || true

    # Build secret env flags at runtime
    SECRET_ENV=(${lib.concatStringsSep " \\\n      " (lib.mapAttrsToList (envVar: secretName:
      "-e \"${envVar}=$(cat ${config.sops.secrets.${secretName}.path})\""
    ) cfg.secretEnvironment)})

    # Build non-secret env flags
    STATIC_ENV=(${lib.concatStringsSep " \\\n      " (lib.mapAttrsToList (k: v:
      "-e \"${k}=${v}\""
    ) containerEnv)})

    exec "$CONTAINER_CLI" run --rm \
      --name goclaw-main \
      "''${SECRET_ENV[@]}" \
      "''${STATIC_ENV[@]}" \
      -v "${cfg.stateDir}:${cfg.stateDir}:rw" \
      -v "${cfg.logsDir}:${cfg.logsDir}:rw" \
      -v "/private/tmp:/private/tmp" \
      ${lib.concatStringsSep " \\\n      " (map (v: "-v \"${v}\"") cfg.extraContainerVolumes)} \
      goclaw:latest
  '';

  # Nginx wrapper (unchanged — nginx runs natively)
  nginxWrapper = pkgs.writeShellScript "goclaw-nginx-wrapper" ''
    set -euo pipefail
    exec /usr/bin/sudo -u ${cfg.user} ${pkgs.nginx}/bin/nginx -c ${cfg._nginxConf}
  '';
in
{
  imports = [ ./default.nix ];

  config = lib.mkMerge [
    {
      services.goclaw.user  = lib.mkDefault "_goclaw";
      services.goclaw.group = lib.mkDefault "_goclaw";
    }
    (lib.mkIf cfg.enable {
      # -----------------------------------------------------------------------
      # Dedicated system user
      # -----------------------------------------------------------------------

      users.users.${cfg.user} = {
        uid         = 309;
        gid         = config.users.groups.${cfg.group}.gid;
        home        = cfg.stateDir;
        shell       = "/usr/bin/false";
        description = "GoClaw AI gateway";
        isHidden    = true;
      };
      users.groups.${cfg.group} = { gid = 309; };
      users.knownUsers  = [ cfg.user ];
      users.knownGroups = [ cfg.group ];

      # -----------------------------------------------------------------------
      # sops secrets
      # -----------------------------------------------------------------------

      sops.secrets = lib.listToAttrs (map (name: {
        inherit name;
        value = {
          owner = cfg.user;
          group = cfg.group;
          mode  = "0400";
        };
      }) secretNames);

      # -----------------------------------------------------------------------
      # PostgreSQL bootstrap + state prep (activation — runs at config switch)
      # -----------------------------------------------------------------------

      system.activationScripts.postActivation.text = lib.mkAfter ''
        echo "Initialising goclaw PostgreSQL database..."
        sudo -u alex ${pgInitScript}

        echo "Preparing goclaw state directories..."
        ${cfg._prepareState}
      '';

      # -----------------------------------------------------------------------
      # LaunchDaemon — gateway (runs as root, drops to _goclaw via container)
      # -----------------------------------------------------------------------

      launchd.daemons.goclaw = {
        serviceConfig = {
          Label              = "com.nextlevelbuilder.goclaw";
          ProgramArguments   = [ "${goclawWrapper}" ];
          RunAtLoad          = true;
          KeepAlive          = true;
          ThrottleInterval   = 10;
          StandardOutPath    = "${cfg.logsDir}/goclaw.log";
          StandardErrorPath  = "${cfg.logsDir}/goclaw.err.log";
          SoftResourceLimits = { NumberOfFiles = 4096; };
          EnvironmentVariables = {
            # Docker shim first so agent sandbox finds it as "docker"
            PATH = lib.makeBinPath (
              [ dockerShim pkgs.coreutils pkgs.bash pkgs.curl ]
            ) + ":${pgBin}:/usr/local/bin:/usr/bin";
          };
        };
      };

      # -----------------------------------------------------------------------
      # LaunchDaemon — web dashboard (standalone nginx, local-only)
      # -----------------------------------------------------------------------

      launchd.daemons.goclaw-ui = lib.mkIf cfg.webUi.enable {
        serviceConfig = {
          Label             = "com.nextlevelbuilder.goclaw-ui";
          ProgramArguments  = [ "${nginxWrapper}" ];
          RunAtLoad         = true;
          KeepAlive         = true;
          ThrottleInterval  = 10;
          StandardOutPath   = "${cfg.logsDir}/goclaw-ui.log";
          StandardErrorPath = "${cfg.logsDir}/goclaw-ui.err.log";
          EnvironmentVariables = { PATH = "/usr/bin"; };
        };
      };
    })
  ];
}
