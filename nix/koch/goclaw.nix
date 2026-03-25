# GoClaw on koch — Telegram channel, OpenRouter provider, Traefik-fronted UI.

{ config, pkgs, inputs, lib, ... }:

let
  steipeteTools = inputs.nix-openclaw.inputs.nix-steipete-tools;
  cfg = config.services.goclaw;
in
{
  imports = [ ../modules/goclaw/nixos.nix ];

  services.goclaw = {
    enable = true;
    uid = 988;
    gid = 988;
    port = 18789;
    stateDir = "/data/state-store/goclaw";
    logsDir = "/var/log/goclaw";
    postgresDSN = "postgres://goclaw@/goclaw?host=/run/postgresql";

    config = {
      gateway.inbound_debounce_ms = 150;

      channels.telegram = {
        enabled = true;
        dm_policy = "allowlist";
        allow_from = [ 560918177 ];
        dm_stream = true;
        group_stream = true;
        reasoning_stream = false;
      };
      agents.defaults = {
        provider = "openai-codex";
        model = "gpt-5.1-codex-mini";
      };
    };

    environment = {
      GOCLAW_PROVIDER   = "openai-codex";
      GOCLAW_MODEL      = "gpt-5.1-codex-mini";
      GOCLAW_LANE_MAIN  = "60";
      GOCLAW_OWNER_IDS  = "alex,560918177,c061959f-6a9a-4b9d-b6ad-744150e692c0";
    };

    secretEnvironment = {
      GOCLAW_GATEWAY_TOKEN      = "goclaw_gateway_token";
      GOCLAW_ENCRYPTION_KEY     = "goclaw_encryption_key";
      GOCLAW_TELEGRAM_TOKEN     = "goclaw_telegram_token";
      GOCLAW_OPENROUTER_API_KEY = "goclaw_openrouter_key";
    };

    extraSkillPaths = [
      { name = "summarize"; path = "${steipeteTools}/tools/summarize/skills/summarize"; }
      { name = "gog";       path = "${steipeteTools}/tools/gogcli/skills/gog"; }
      { name = "goplaces";  path = "${steipeteTools}/tools/goplaces/skills/goplaces"; }
      { name = "camsnap";   path = "${steipeteTools}/tools/camsnap/skills/camsnap"; }
      { name = "sag";       path = "${steipeteTools}/tools/sag/skills/sag"; }
      { name = "sonoscli";  path = "${steipeteTools}/tools/sonoscli/skills/sonoscli"; }
      { name = "xuezh";     path = "${inputs.xuezh}/skills/xuezh"; }
    ];

    extraContainerOptions = [
      "--add-host=mandelbrot.tuxedo-burbot.ts.net:100.64.42.28"  # Tailscale IP — ollama via Tailscale Serve
    ];

    webUi.enable = true;
    webUi.hostName = "goclaw.koch.brians.skin";

    browser.sidecar.enable = true;
  };

  # Traefik routing (koch-specific — public TLS via deSEC)
  services.traefik.dynamicConfigOptions.http.routers.goclaw = {
    rule = "Host(`goclaw.koch.brians.skin`)";
    service = "goclaw";
    tls.certResolver = "desec";
  };
  services.traefik.dynamicConfigOptions.http.services.goclaw.loadBalancer.servers = [
    { url = "http://localhost:${toString cfg.uiPort}"; }
  ];
}
