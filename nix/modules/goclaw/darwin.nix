# GoClaw darwin implementation — launchd agents, Homebrew PostgreSQL, standalone nginx.
#
# Handles: database bootstrap (activation + wrapper safety net), secret reading
# in wrapper script, launchd agents for gateway and web UI.

{ config, pkgs, lib, ... }:

let
  cfg = config.services.goclaw;

  secretNames = lib.unique (lib.attrValues cfg.secretEnvironment);

  # Homebrew PostgreSQL 17 paths (Apple Silicon)
  pgBin = "/opt/homebrew/opt/postgresql@17/bin";
  pgUser = "goclaw";
  pgDatabase = "goclaw";

  # Idempotent database bootstrap — creates role, database, pgcrypto + pgvector.
  # Homebrew PG uses trust auth for local connections, so no password needed.
  pgInitScript = pkgs.writeShellScript "goclaw-pg-init" ''
    set -euo pipefail
    PSQL="${pgBin}/psql"
    CREATEUSER="${pgBin}/createuser"
    CREATEDB="${pgBin}/createdb"

    if ! "$PSQL" -h localhost -c '\q' postgres 2>/dev/null; then
      echo "goclaw-pg-init: PostgreSQL not reachable, skipping"
      exit 0
    fi

    if ! "$PSQL" -h localhost -tAc "SELECT 1 FROM pg_roles WHERE rolname='${pgUser}'" postgres | grep -q 1; then
      echo "goclaw-pg-init: creating role '${pgUser}'"
      "$CREATEUSER" -h localhost --no-superuser --no-createdb --no-createrole "${pgUser}"
    fi

    if ! "$PSQL" -h localhost -tAc "SELECT 1 FROM pg_database WHERE datname='${pgDatabase}'" postgres | grep -q 1; then
      echo "goclaw-pg-init: creating database '${pgDatabase}'"
      "$CREATEDB" -h localhost --owner="${pgUser}" "${pgDatabase}"
    fi

    "$PSQL" -h localhost -d "${pgDatabase}" -c 'CREATE EXTENSION IF NOT EXISTS "pgcrypto";' 2>/dev/null || true
    "$PSQL" -h localhost -d "${pgDatabase}" -c 'CREATE EXTENSION IF NOT EXISTS "vector";' 2>/dev/null || \
      echo "goclaw-pg-init: pgvector not available (brew install pgvector)"
  '';

  # Wrapper: DB init → state prep → read secrets → export env → exec goclaw.
  # On darwin there's no ExecStartPre, so the wrapper does everything.
  goclawWrapper = pkgs.writeShellScript "goclaw-wrapper" ''
    set -euo pipefail

    ${pgInitScript}
    ${cfg._prepareState}

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (envVar: secretName: ''
      ${envVar}="$(cat ${config.sops.secrets.${secretName}.path})"
      export ${envVar}
    '') cfg.secretEnvironment)}

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
      export ${k}="${v}"
    '') cfg._commonEnv)}

    exec ${cfg.package}/bin/goclaw
  '';
in
{
  imports = [ ./default.nix ];

  config = lib.mkIf cfg.enable {
    # -----------------------------------------------------------------------
    # sops secrets — bare (no owner/group on darwin)
    # -----------------------------------------------------------------------

    sops.secrets = lib.listToAttrs (map (name: {
      inherit name;
      value = {};
    }) secretNames);

    # -----------------------------------------------------------------------
    # PostgreSQL — activation script + wrapper safety net
    # -----------------------------------------------------------------------

    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "Initialising goclaw PostgreSQL database..."
      sudo -u alex ${pgInitScript}
    '';

    # -----------------------------------------------------------------------
    # Launchd agent — gateway
    # -----------------------------------------------------------------------

    launchd.user.agents.goclaw = {
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
          PATH = lib.makeBinPath [ pkgs.coreutils pkgs.bash pkgs.curl ] + ":${pgBin}";
        };
      };
    };

    # -----------------------------------------------------------------------
    # Launchd agent — web dashboard (standalone nginx, local-only)
    # -----------------------------------------------------------------------

    launchd.user.agents.goclaw-ui = lib.mkIf cfg.webUi.enable {
      serviceConfig = {
        Label = "com.nextlevelbuilder.goclaw-ui";
        ProgramArguments = [ "${pkgs.nginx}/bin/nginx" "-c" "${cfg._nginxConf}" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardOutPath = "${cfg.logsDir}/goclaw-ui.log";
        StandardErrorPath = "${cfg.logsDir}/goclaw-ui.err.log";
      };
    };
  };
}
