# GoClaw — multi-agent AI gateway on nix-darwin
#
# Mirrors koch's openclaw security posture adapted for launchd:
# - Loopback-only binding (127.0.0.1)
# - sops-nix secrets (age-encrypted, never in config)
# - Slack channel with allowlist + DM-only policy
# - User-level launchd agent (not root)
#
# PostgreSQL 17 + pgvector managed via Homebrew (see configuration.nix).
# Database, role, and extensions created declaratively via activation script.
# Secrets decrypted by sops-nix darwin module.

{ config, pkgs, lib, ... }:

let
  goclawPkg = pkgs.goclaw;

  dataDir = "/Users/alex/.goclaw";
  logsDir = "/Users/alex/Library/Logs/goclaw";

  # Homebrew PostgreSQL 17 paths (Apple Silicon)
  pgBin = "/opt/homebrew/opt/postgresql@17/bin";

  # Dedicated role + database, local trust auth — no password needed
  pgUser = "goclaw";
  pgDatabase = "goclaw";
  pgDSN = "postgres://${pgUser}@localhost:5432/${pgDatabase}?sslmode=disable";

  # Idempotent database bootstrap — creates role, database, and pgvector extension.
  # Runs as the macOS user (Homebrew PG superuser) via activation and again in the
  # wrapper as a safety net.
  pgInitScript = pkgs.writeShellScript "goclaw-pg-init" ''
    set -euo pipefail
    PSQL="${pgBin}/psql"
    CREATEUSER="${pgBin}/createuser"
    CREATEDB="${pgBin}/createdb"

    # Bail if PostgreSQL is not running
    if ! "$PSQL" -h localhost -c '\q' postgres 2>/dev/null; then
      echo "goclaw-pg-init: PostgreSQL not reachable, skipping DB init"
      exit 0
    fi

    # Create dedicated role (LOGIN, no superuser, no createdb)
    if ! "$PSQL" -h localhost -tAc "SELECT 1 FROM pg_roles WHERE rolname='${pgUser}'" postgres | grep -q 1; then
      echo "goclaw-pg-init: creating role '${pgUser}'"
      "$CREATEUSER" -h localhost --no-superuser --no-createdb --no-createrole "${pgUser}"
    fi

    # Create database owned by the goclaw role
    if ! "$PSQL" -h localhost -tAc "SELECT 1 FROM pg_database WHERE datname='${pgDatabase}'" postgres | grep -q 1; then
      echo "goclaw-pg-init: creating database '${pgDatabase}'"
      "$CREATEDB" -h localhost --owner="${pgUser}" "${pgDatabase}"
    fi

    # Enable pgvector extension (requires superuser, run as alex)
    "$PSQL" -h localhost -d "${pgDatabase}" -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || \
      echo "goclaw-pg-init: pgvector extension not available (install via brew install pgvector)"
  '';

  configJson = pkgs.writeText "goclaw-config.json" (builtins.toJSON {
    gateway = {
      host = "127.0.0.1";
      port = 18790;
    };
    channels = {
      slack = {
        enabled = true;
        dm_policy = "allowlist";
        group_policy = "disabled";
        require_mention = true;
      };
    };
    agents = {
      defaults = {
        workspace = "${dataDir}/workspace";
      };
    };
    database = {};
  });

  # Wrapper script: ensures DB exists, reads sops secrets, exec's goclaw.
  # Mirrors koch's prepareEnv pattern but for launchd (no ExecStartPre).
  goclawWrapper = pkgs.writeShellScript "goclaw-wrapper" ''
    set -euo pipefail

    # Ensure data and log directories exist
    mkdir -p "${dataDir}/workspace" "${logsDir}"

    # Safety-net DB init (idempotent) — handles the case where PostgreSQL
    # wasn't running during darwin-rebuild activation
    ${pgInitScript}

    # Read secrets from sops-nix paths
    GOCLAW_GATEWAY_TOKEN="$(cat ${config.sops.secrets.goclaw_gateway_token.path})"
    GOCLAW_ENCRYPTION_KEY="$(cat ${config.sops.secrets.goclaw_encryption_key.path})"
    GOCLAW_SLACK_BOT_TOKEN="$(cat ${config.sops.secrets.goclaw_slack_bot_token.path})"
    GOCLAW_SLACK_APP_TOKEN="$(cat ${config.sops.secrets.goclaw_slack_app_token.path})"
    GOCLAW_ANTHROPIC_API_KEY="$(cat ${config.sops.secrets.goclaw_anthropic_api_key.path})"

    export GOCLAW_GATEWAY_TOKEN
    export GOCLAW_ENCRYPTION_KEY
    export GOCLAW_SLACK_BOT_TOKEN
    export GOCLAW_SLACK_APP_TOKEN
    export GOCLAW_ANTHROPIC_API_KEY

    # Deterministic DSN — dedicated role, local trust auth, no password
    export GOCLAW_POSTGRES_DSN="${pgDSN}"

    # Bind loopback only
    export GOCLAW_HOST="127.0.0.1"
    export GOCLAW_PORT="18790"

    # Point to nix-generated config and bundled assets
    export GOCLAW_CONFIG="${configJson}"
    export GOCLAW_MIGRATIONS_DIR="${goclawPkg}/share/goclaw/migrations"
    export GOCLAW_BUNDLED_SKILLS_DIR="${goclawPkg}/share/goclaw/skills"
    export GOCLAW_AUTO_UPGRADE="true"

    # Disable telemetry
    export GOCLAW_TELEMETRY_ENABLED="false"

    exec ${goclawPkg}/bin/goclaw
  '';
in
{
  # ---------------------------------------------------------------------------
  # sops secrets — age-encrypted, decrypted at activation
  # ---------------------------------------------------------------------------

  sops.secrets."goclaw_gateway_token" = {};
  sops.secrets."goclaw_encryption_key" = {};
  sops.secrets."goclaw_slack_bot_token" = {};
  sops.secrets."goclaw_slack_app_token" = {};
  sops.secrets."goclaw_anthropic_api_key" = {};

  # ---------------------------------------------------------------------------
  # PostgreSQL — declarative role, database, and pgvector extension
  #
  # Runs during darwin-rebuild activation. If PostgreSQL isn't up yet,
  # the wrapper script retries at launch (idempotent).
  # ---------------------------------------------------------------------------

  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "Initialising goclaw PostgreSQL database..."
    sudo -u alex ${pgInitScript}
  '';

  # ---------------------------------------------------------------------------
  # Launchd user agent — equivalent to koch's systemd service
  # ---------------------------------------------------------------------------

  launchd.user.agents.goclaw = {
    serviceConfig = {
      Label = "com.nextlevelbuilder.goclaw";
      ProgramArguments = [ "${goclawWrapper}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 10;
      StandardOutPath = "${logsDir}/goclaw.log";
      StandardErrorPath = "${logsDir}/goclaw.err.log";
      SoftResourceLimits = {
        NumberOfFiles = 4096;
      };
      EnvironmentVariables = {
        PATH = lib.makeBinPath [ pkgs.coreutils pkgs.bash ] + ":${pgBin}";
      };
    };
  };
}
