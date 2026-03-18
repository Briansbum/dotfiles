# GoClaw darwin implementation — isolated system user, LaunchDaemons, Homebrew PostgreSQL.
#
# Process isolation: dedicated _goclaw user with no login shell, own home directory,
# and no access to /Users/alex. Runs as system-level LaunchDaemons (not user agents)
# so it starts at boot independent of any login session.
#
# Sandbox: when sandbox.enable = true, agent code execution runs inside Apple
# Containers (macOS 26+). A docker→container CLI shim translates goclaw's Docker
# calls to Apple Container equivalents — each sandbox gets its own lightweight VM.

{ config, pkgs, lib, ... }:

let
  cfg = config.services.goclaw;

  secretNames = lib.unique (lib.attrValues cfg.secretEnvironment);

  # Homebrew PostgreSQL 17 paths (Apple Silicon)
  pgBin = "/opt/homebrew/opt/postgresql@17/bin";

  pgRole = "goclaw";
  pgDatabase = "goclaw";

  # docker→container shim: translates goclaw's Docker sandbox calls to Apple Container CLI
  dockerShim = pkgs.writeShellScriptBin "docker" (builtins.readFile ./docker-to-container-shim.sh);

  # Idempotent database bootstrap — runs as alex (Homebrew PG superuser).
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

  # Build the sandbox container image from goclaw's bundled Dockerfile
  sandboxImageSetup = pkgs.writeShellScript "goclaw-sandbox-image-setup" ''
    set -euo pipefail
    CONTAINER_CLI="/usr/local/bin/container"

    # Ensure Apple Container system is running
    if ! "$CONTAINER_CLI" system status >/dev/null 2>&1; then
      echo "goclaw-sandbox: starting Apple Container system..."
      "$CONTAINER_CLI" system start
      sleep 2
    fi

    # Build sandbox image if it doesn't exist
    if ! "$CONTAINER_CLI" image inspect "${cfg.sandbox.image}" >/dev/null 2>&1; then
      echo "goclaw-sandbox: building sandbox image ${cfg.sandbox.image}..."
      "$CONTAINER_CLI" build \
        -t "${cfg.sandbox.image}" \
        -f ${cfg.package}/share/goclaw/Dockerfile.sandbox \
        ${cfg.package}/share/goclaw
    else
      echo "goclaw-sandbox: image ${cfg.sandbox.image} already exists"
    fi
  '';

  # Wrapper: DB init → state prep → sandbox setup → secrets → exec goclaw.
  goclawWrapper = pkgs.writeShellScript "goclaw-wrapper" ''
    set -euo pipefail

    # DB init needs to run as alex (Homebrew PG superuser)
    /usr/bin/sudo -u alex ${pgInitScript}

    # Prepare state directories (runs as root, chown handled by _prepareState)
    ${cfg._prepareState}

    ${lib.optionalString cfg.sandbox.enable ''
    # Build sandbox image and ensure Apple Container system is running
    ${sandboxImageSetup}
    ''}

    # Build environment for the goclaw process
    ENV_FILE="${cfg.stateDir}/.env"
    umask 077
    {
      ${lib.concatStringsSep "\n    " (lib.mapAttrsToList (envVar: secretName:
        "printf '${envVar}=%s\\n' \"$(cat ${config.sops.secrets.${secretName}.path})\""
      ) cfg.secretEnvironment)}
      ${lib.concatStringsSep "\n    " (lib.mapAttrsToList (k: v:
        "printf '${k}=${v}\\n'"
      ) cfg._commonEnv)}
    } > "$ENV_FILE"
    chown ${cfg.user}:${cfg.group} "$ENV_FILE"

    # Drop privileges and exec goclaw as the dedicated user
    exec /usr/bin/sudo -u ${cfg.user} /usr/bin/env \
      $(cat "$ENV_FILE" | /usr/bin/sed 's/^//' | /usr/bin/tr '\n' ' ') \
      ${cfg.package}/bin/goclaw
  '';

  # Nginx wrapper
  nginxWrapper = pkgs.writeShellScript "goclaw-nginx-wrapper" ''
    set -euo pipefail
    exec /usr/bin/sudo -u ${cfg.user} ${pkgs.nginx}/bin/nginx -c ${cfg._nginxConf}
  '';
in
{
  imports = [ ./default.nix ];

  config = lib.mkMerge [
    {
      # Default to macOS system user naming convention
      services.goclaw.user = lib.mkDefault "_goclaw";
      services.goclaw.group = lib.mkDefault "_goclaw";
    }
    (lib.mkIf cfg.enable {
    # -----------------------------------------------------------------------
    # Dedicated system user — no login shell, hidden, isolated from /Users/alex
    # -----------------------------------------------------------------------

    users.users.${cfg.user} = {
      uid = 309;
      gid = config.users.groups.${cfg.group}.gid;
      home = cfg.stateDir;
      shell = "/usr/bin/false";
      description = "GoClaw AI gateway";
      isHidden = true;
    };
    users.groups.${cfg.group} = {
      gid = 309;
    };
    users.knownUsers = [ cfg.user ];
    users.knownGroups = [ cfg.group ];

    # -----------------------------------------------------------------------
    # sops secrets — owned by the goclaw user
    # -----------------------------------------------------------------------

    sops.secrets = lib.listToAttrs (map (name: {
      inherit name;
      value = {
        owner = cfg.user;
        group = cfg.group;
        mode = "0400";
      };
    }) secretNames);

    # -----------------------------------------------------------------------
    # PostgreSQL — activation script (runs as alex, the PG superuser)
    # -----------------------------------------------------------------------

    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "Initialising goclaw PostgreSQL database..."
      sudo -u alex ${pgInitScript}

      echo "Preparing goclaw state directories..."
      ${cfg._prepareState}

      ${lib.optionalString cfg.sandbox.enable ''
      echo "Setting up goclaw sandbox image..."
      ${sandboxImageSetup}
      ''}
    '';

    # -----------------------------------------------------------------------
    # LaunchDaemon — gateway (system-level, runs at boot, not tied to login)
    # -----------------------------------------------------------------------

    launchd.daemons.goclaw = {
      serviceConfig = {
        Label = "com.nextlevelbuilder.goclaw";
        ProgramArguments = [ "${goclawWrapper}" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardOutPath = "${cfg.logsDir}/goclaw.log";
        StandardErrorPath = "${cfg.logsDir}/goclaw.err.log";
        SoftResourceLimits = { NumberOfFiles = 4096; };
        EnvironmentVariables = {
          # docker shim first in PATH so goclaw's sandbox finds it as "docker"
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
        Label = "com.nextlevelbuilder.goclaw-ui";
        ProgramArguments = [ "${nginxWrapper}" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardOutPath = "${cfg.logsDir}/goclaw-ui.log";
        StandardErrorPath = "${cfg.logsDir}/goclaw-ui.err.log";
        EnvironmentVariables = {
          PATH = "/usr/bin";
        };
      };
    };
  })
  ];
}
