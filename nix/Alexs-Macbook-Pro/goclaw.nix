# GoClaw on Alexs-MacBook-Pro — Slack channel, Anthropic provider, local-only UI.
#
# Runs as dedicated _goclaw system user with no access to /Users/alex.
# State in /var/lib/goclaw, logs in /var/log/goclaw.

{ ... }:

{
  imports = [ ../modules/goclaw/darwin.nix ];

  services.goclaw = {
    enable = true;
    port = 18790;
    stateDir = "/var/lib/goclaw";
    logsDir = "/var/log/goclaw";
    postgresDSN = "postgres://goclaw@localhost:5432/goclaw?sslmode=disable";

    config = {
      channels.slack = {
        enabled = true;
        dm_policy = "allowlist";
        group_policy = "disabled";
        require_mention = true;
      };
      agents.defaults.workspace = "/var/lib/goclaw/workspace";
      database = {};
    };

    secretEnvironment = {
      GOCLAW_GATEWAY_TOKEN = "goclaw_gateway_token";
      GOCLAW_ENCRYPTION_KEY = "goclaw_encryption_key";
      GOCLAW_SLACK_BOT_TOKEN = "goclaw_slack_bot_token";
      GOCLAW_SLACK_APP_TOKEN = "goclaw_slack_app_token";
      GOCLAW_ANTHROPIC_API_KEY = "goclaw_anthropic_api_key";
    };

    webUi.enable = true;
  };
}
