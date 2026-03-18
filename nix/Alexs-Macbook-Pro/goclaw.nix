# GoClaw on Alexs-MacBook-Pro — Slack channel, Anthropic provider, local-only UI.

{ ... }:

{
  imports = [ ../modules/goclaw/darwin.nix ];

  services.goclaw = {
    enable = true;
    port = 18790;
    stateDir = "/Users/alex/.goclaw";
    logsDir = "/Users/alex/Library/Logs/goclaw";
    postgresDSN = "postgres://goclaw@localhost:5432/goclaw?sslmode=disable";

    config = {
      channels.slack = {
        enabled = true;
        dm_policy = "allowlist";
        group_policy = "disabled";
        require_mention = true;
      };
      agents.defaults.workspace = "/Users/alex/.goclaw/workspace";
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
