# GoClaw — multi-agent AI gateway on nix-darwin
#
# Mirrors koch's openclaw security posture adapted for launchd:
# - Loopback-only binding (127.0.0.1)
# - sops-nix secrets (age-encrypted, never in config)
# - Slack channel with allowlist + DM-only policy
# - User-level launchd agent (not root)
#
# PostgreSQL 17 + pgvector managed via Homebrew (see configuration.nix).
# Secrets decrypted by sops-nix darwin module into /run/user/501/secrets/.

{ config, pkgs, lib, ... }:

let
  goclawPkg = pkgs.goclaw;

  dataDir = "/Users/alex/.goclaw";
  logsDir = "/Users/alex/Library/Logs/goclaw";

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

  # Wrapper script: reads sops secrets, assembles env, exec's goclaw.
  # Mirrors koch's prepareEnv pattern but for launchd (no ExecStartPre).
  goclawWrapper = pkgs.writeShellScript "goclaw-wrapper" ''
    set -euo pipefail

    # Ensure data and log directories exist
    mkdir -p "${dataDir}/workspace" "${logsDir}"

    # Read secrets from sops-nix paths
    GOCLAW_GATEWAY_TOKEN="$(cat ${config.sops.secrets.goclaw_gateway_token.path})"
    GOCLAW_ENCRYPTION_KEY="$(cat ${config.sops.secrets.goclaw_encryption_key.path})"
    GOCLAW_SLACK_BOT_TOKEN="$(cat ${config.sops.secrets.goclaw_slack_bot_token.path})"
    GOCLAW_SLACK_APP_TOKEN="$(cat ${config.sops.secrets.goclaw_slack_app_token.path})"
    GOCLAW_POSTGRES_DSN="$(cat ${config.sops.secrets.goclaw_postgres_dsn.path})"
    GOCLAW_ANTHROPIC_API_KEY="$(cat ${config.sops.secrets.goclaw_anthropic_api_key.path})"

    export GOCLAW_GATEWAY_TOKEN
    export GOCLAW_ENCRYPTION_KEY
    export GOCLAW_SLACK_BOT_TOKEN
    export GOCLAW_SLACK_APP_TOKEN
    export GOCLAW_POSTGRES_DSN
    export GOCLAW_ANTHROPIC_API_KEY

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
  sops.secrets."goclaw_postgres_dsn" = {};
  sops.secrets."goclaw_anthropic_api_key" = {};

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
        PATH = lib.makeBinPath [ pkgs.coreutils pkgs.bash ];
      };
    };
  };
}
