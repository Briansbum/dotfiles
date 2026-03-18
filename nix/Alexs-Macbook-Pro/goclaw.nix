# GoClaw on nix-darwin — platform-specific plumbing for launchd + Homebrew PostgreSQL.
#
# Shared options and config generation live in ../modules/goclaw.nix.
# This file provides: Homebrew PG bootstrap, sops secret wiring, launchd agents,
# and local-only web dashboard (no Traefik/TLS — this is the work Mac).

{ config, pkgs, lib, ... }:

let
  cfg = config.services.goclaw;

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

  # Wrapper: DB init → state prep → secrets → exec goclaw
  # On darwin there's no ExecStartPre, so the wrapper does everything.
  goclawWrapper = pkgs.writeShellScript "goclaw-wrapper" ''
    set -euo pipefail

    # Idempotent DB init (safety net if PG wasn't up during activation)
    ${pgInitScript}

    # Prepare writable state directories
    ${cfg._prepareState}

    # Read secrets from sops-nix paths
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (envVar: secretName: ''
      ${envVar}="$(cat ${config.sops.secrets.${secretName}.path})"
      export ${envVar}
    '') cfg.secretEnvironment)}

    # Export common environment
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
      export ${k}="${v}"
    '') cfg._commonEnv)}

    exec ${cfg.package}/bin/goclaw
  '';
in
{
  imports = [ ../modules/goclaw.nix ];

  # ---------------------------------------------------------------------------
  # GoClaw options — Slack channel, Anthropic provider, darwin paths
  # ---------------------------------------------------------------------------

  services.goclaw = {
    enable = true;
    port = 18790;
    uiPort = 18780;
    stateDir = "/Users/alex/.goclaw";
    logsDir = "/Users/alex/Library/Logs/goclaw";
    postgresDSN = "postgres://${pgUser}@localhost:5432/${pgDatabase}?sslmode=disable";

    config = {
      channels.slack = {
        enabled = true;
        dm_policy = "allowlist";
        group_policy = "disabled";
        require_mention = true;
      };
      agents.defaults = {
        workspace = "/Users/alex/.goclaw/workspace";
      };
      database = {};
    };

    secrets = [
      "goclaw_gateway_token"
      "goclaw_encryption_key"
      "goclaw_slack_bot_token"
      "goclaw_slack_app_token"
      "goclaw_anthropic_api_key"
    ];

    secretEnvironment = {
      GOCLAW_GATEWAY_TOKEN = "goclaw_gateway_token";
      GOCLAW_ENCRYPTION_KEY = "goclaw_encryption_key";
      GOCLAW_SLACK_BOT_TOKEN = "goclaw_slack_bot_token";
      GOCLAW_SLACK_APP_TOKEN = "goclaw_slack_app_token";
      GOCLAW_ANTHROPIC_API_KEY = "goclaw_anthropic_api_key";
    };

    webUi.enable = true;
  };

  # ---------------------------------------------------------------------------
  # PostgreSQL — declarative role, database, and extensions
  # ---------------------------------------------------------------------------

  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "Initialising goclaw PostgreSQL database..."
    sudo -u alex ${pgInitScript}
  '';

  # ---------------------------------------------------------------------------
  # Launchd user agents
  # ---------------------------------------------------------------------------

  launchd.user.agents.goclaw = {
    serviceConfig = {
      Label = "com.nextlevelbuilder.goclaw";
      ProgramArguments = [ "${goclawWrapper}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 10;
      StandardOutPath = "${cfg.logsDir}/goclaw.log";
      StandardErrorPath = "${cfg.logsDir}/goclaw.err.log";
      SoftResourceLimits = {
        NumberOfFiles = 4096;
      };
      EnvironmentVariables = {
        PATH = lib.makeBinPath [ pkgs.coreutils pkgs.bash pkgs.curl ] + ":${pgBin}";
      };
    };
  };

  # Web dashboard — local-only nginx serving SPA + proxying to goclaw
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
}
