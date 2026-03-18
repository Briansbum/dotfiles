# GoClaw darwin implementation — isolated system user, LaunchDaemons, Homebrew PostgreSQL.
#
# Process isolation: dedicated _goclaw user with no login shell, own home directory,
# and no access to /Users/alex. Runs as system-level LaunchDaemons (not user agents)
# so it starts at boot independent of any login session.

{ config, pkgs, lib, ... }:

let
  cfg = config.services.goclaw;

  secretNames = lib.unique (lib.attrValues cfg.secretEnvironment);

  # Homebrew PostgreSQL 17 paths (Apple Silicon)
  pgBin = "/opt/homebrew/opt/postgresql@17/bin";

  # The PG role name matches the option default — override pgRole in host config
  # if cfg.user differs from the PG role you want.
  pgRole = "goclaw";
  pgDatabase = "goclaw";

  # Idempotent database bootstrap — runs as alex (Homebrew PG superuser) to create
  # the dedicated role + database + extensions. The goclaw process then connects
  # as its own role via TCP trust auth.
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

  # Wrapper: DB init (as alex via sudo) → state prep (as root) → drop to goclaw → exec.
  # LaunchDaemons run as root by default; the wrapper does privileged setup then
  # exec's goclaw as the dedicated user.
  goclawWrapper = pkgs.writeShellScript "goclaw-wrapper" ''
    set -euo pipefail

    # DB init needs to run as alex (Homebrew PG superuser)
    /usr/bin/sudo -u alex ${pgInitScript}

    # Prepare state directories (runs as root, chown handled by _prepareState)
    ${cfg._prepareState}

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

  # Nginx wrapper — also needs to run as the goclaw user
  nginxWrapper = pkgs.writeShellScript "goclaw-nginx-wrapper" ''
    set -euo pipefail
    exec /usr/bin/sudo -u ${cfg.user} ${pkgs.nginx}/bin/nginx -c ${cfg._nginxConf}
  '';
in
{
  imports = [ ./default.nix ];

  # Default to macOS system user naming convention
  services.goclaw.user = lib.mkDefault "_goclaw";
  services.goclaw.group = lib.mkDefault "_goclaw";

  config = lib.mkIf cfg.enable {
    # -----------------------------------------------------------------------
    # Dedicated system user — no login shell, hidden, isolated from /Users/alex
    # -----------------------------------------------------------------------

    users.users.${cfg.user} = {
      uid = 350;
      gid = config.users.groups.${cfg.group}.gid;
      home = cfg.stateDir;
      shell = "/usr/bin/false";
      description = "GoClaw AI gateway";
      isHidden = true;
    };
    users.groups.${cfg.group} = {
      gid = 350;
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
          PATH = lib.makeBinPath [ pkgs.coreutils pkgs.bash pkgs.curl ] + ":${pgBin}:/usr/bin";
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
  };
}
