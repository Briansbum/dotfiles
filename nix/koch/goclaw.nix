# GoClaw on koch — Telegram channel, OpenRouter provider, Traefik-fronted UI.

{ config, pkgs, inputs, lib, ... }:

let
  steipeteTools = inputs.nix-openclaw.inputs.nix-steipete-tools;
  cfg = config.services.goclaw;
  telegramCfg = cfg.config.channels.telegram;
  webhookMode = (telegramCfg.connection_mode or "") == "webhook";
  webhookPath = "/" + lib.removePrefix "/" (telegramCfg.webhook_path or "/telegram/webhook");
in
{
  imports = [ ../modules/goclaw/nixos.nix ];

  services.goclaw = {
    enable = true;
    port = 18789;
    stateDir = "/data/state-store/goclaw";
    logsDir = "/var/log/goclaw";
    postgresDSN = "postgres://goclaw@/goclaw?host=/run/postgresql";

    config = {
      gateway.inbound_debounce_ms = 150;

      channels.telegram = {
        enabled = true;
        connection_mode = "webhook";
        webhook_path = "/telegram-webhook-goclaw";
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
      GOCLAW_PROVIDER = "openai-codex";
      GOCLAW_MODEL = "gpt-5.1-codex-mini";
      GOCLAW_LANE_MAIN = "60";
      ROD_BROWSER_BIN = "${pkgs.chromium}/bin/chromium";
      GOCLAW_OWNER_IDS = "alex,560918177,c061959f-6a9a-4b9d-b6ad-744150e692c0";
    };

    secretEnvironment = {
      GOCLAW_GATEWAY_TOKEN = "goclaw_gateway_token";
      GOCLAW_ENCRYPTION_KEY = "goclaw_encryption_key";
      GOCLAW_TELEGRAM_TOKEN = "goclaw_telegram_token";
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

    webUi.enable = true;
    webUi.hostName = "goclaw.koch.brians.skin";
  };

  # Add xuezh + chromium to systemd PATH
  systemd.services.goclaw.path = [
    inputs.xuezh.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.chromium
  ];

  # Traefik routing (koch-specific — public TLS via deSEC)
  services.traefik.dynamicConfigOptions.http.routers.goclaw = {
    rule = "Host(`goclaw.koch.brians.skin`)";
    service = "goclaw";
    tls.certResolver = "desec";
  };
  services.traefik.dynamicConfigOptions.http.services.goclaw.loadBalancer.servers = [
    { url = "http://localhost:${toString cfg.uiPort}"; }
  ];

  systemd.services.goclaw-telegram-webhook-assert = lib.mkIf webhookMode {
    description = "Assert Telegram webhook points to Tailscale Funnel";
    wantedBy = [ "goclaw.service" ];
    partOf = [ "goclaw.service" ];
    after = [
      "goclaw.service"
      "tailscaled.service"
      "goclaw-telegram-webhook-ts.service"
    ];
    wants = [
      "tailscaled.service"
      "goclaw-telegram-webhook-ts.service"
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "goclaw-telegram-webhook-assert" ''
        set -euo pipefail

        env_file=/run/goclaw/env
        if [ ! -f "$env_file" ]; then
          echo "goclaw env file missing: $env_file" >&2
          exit 1
        fi

        token="$(${pkgs.gawk}/bin/awk -F= '$1=="GOCLAW_TELEGRAM_TOKEN"{print substr($0, index($0, "=")+1)}' "$env_file")"
        if [ -z "$token" ]; then
          echo "GOCLAW_TELEGRAM_TOKEN is missing in $env_file" >&2
          exit 1
        fi

        dns_name="$(${config.services.tailscale.package}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -r '.Self.DNSName // empty' | ${pkgs.gnused}/bin/sed 's/\.$//')"
        if [ -z "$dns_name" ]; then
          echo "tailscale DNS name is empty" >&2
          exit 1
        fi

        expected_url="https://$dns_name${webhookPath}"
        actual_url="$(${pkgs.curl}/bin/curl -fsS --max-time 20 "https://api.telegram.org/bot$token/getWebhookInfo" | ${pkgs.jq}/bin/jq -r '.result.url // empty')"

        if [ "$actual_url" != "$expected_url" ]; then
          webhook_secret="$(${pkgs.gawk}/bin/awk -F= '$1=="GOCLAW_TELEGRAM_WEBHOOK_SECRET"{print substr($0, index($0, "=")+1)}' "$env_file")"

          echo "Telegram webhook mismatch; upserting to Funnel URL"
          echo "expected: $expected_url"
          echo "actual:   $actual_url"

          if [ -n "$webhook_secret" ]; then
            ${pkgs.curl}/bin/curl -fsS --max-time 20 \
              --data-urlencode "url=$expected_url" \
              --data-urlencode "secret_token=$webhook_secret" \
              --data-urlencode 'allowed_updates=["message","edited_message","callback_query","my_chat_member"]' \
              "https://api.telegram.org/bot$token/setWebhook" >/dev/null
          else
            ${pkgs.curl}/bin/curl -fsS --max-time 20 \
              --data-urlencode "url=$expected_url" \
              --data-urlencode 'allowed_updates=["message","edited_message","callback_query","my_chat_member"]' \
              "https://api.telegram.org/bot$token/setWebhook" >/dev/null
          fi

          actual_url="$(${pkgs.curl}/bin/curl -fsS --max-time 20 "https://api.telegram.org/bot$token/getWebhookInfo" | ${pkgs.jq}/bin/jq -r '.result.url // empty')"
        fi

        if [ "$actual_url" != "$expected_url" ]; then
          echo "Telegram webhook upsert failed" >&2
          echo "expected: $expected_url" >&2
          echo "actual:   $actual_url" >&2
          exit 1
        fi

        echo "Telegram webhook OK: $actual_url"
      '';
    };
  };
}
