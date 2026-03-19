# GoClaw on Alexs-MacBook-Pro — Slack channel, Anthropic provider, local-only UI.
#
# Runs as dedicated _goclaw system user with no access to /Users/alex.
# State in /var/lib/goclaw, logs in /var/log/goclaw.
# Agent code execution sandboxed via Apple Containers (macOS 26+).

{ ... }:

{
  imports = [ ../modules/goclaw/darwin.nix ];

  services.goclaw = {
    enable = true;
    port = 18790;
    stateDir = "/var/lib/goclaw";
    logsDir = "/var/log/goclaw";
    # Use Unix socket so the Apple Container can reach Homebrew PostgreSQL
    # without TCP networking complexity. Homebrew PG puts its socket in /private/tmp,
    # which is mounted into the container.
    postgresDSN = "postgres://goclaw@/goclaw?host=/private/tmp";

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

    # Apple Containers sandbox — agent code runs in lightweight VMs
    sandbox = {
      enable = true;
      mode = "non-main";
      memoryMB = 512;
      cpus = 1.0;
      scope = "shared"; # one long-lived container — auth state persists
      workspaceAccess = "rw";
      env = {
        # Store Claude auth inside the workspace mount so it survives
        # container recreation (workspace is a host volume at stateDir/workspace)
        CLAUDE_CONFIG_DIR = "/workspace/.claude";
        HOME = "/workspace";
      };
    };

    webUi.enable = true;
  };
}
