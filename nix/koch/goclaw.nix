# GoClaw on NixOS — platform-specific plumbing for systemd + NixOS PostgreSQL.
#
# Shared options and config generation live in ../modules/goclaw.nix.
# This file provides: NixOS PostgreSQL, systemd service with sandboxing,
# sops secret ownership, nginx + Traefik web dashboard, skills from flake inputs.

{ config, pkgs, inputs, lib, ... }:

let
  cfg = config.services.goclaw;
  goclawPkg = cfg.package;
  grocyMcp = pkgs.grocy-mcp;
  xuezhPkg = inputs.xuezh.packages.${pkgs.system}.default;
  steipeteTools = inputs.nix-openclaw.inputs.nix-steipete-tools;

  prepareEnv = pkgs.writeShellScript "prepare-goclaw-env" ''
    set -euo pipefail
    env_path="/run/goclaw/env"
    umask 077
    {
      printf 'GOCLAW_GATEWAY_TOKEN=%s\n' "$(cat "$1")"
      printf 'GOCLAW_ENCRYPTION_KEY=%s\n' "$(cat "$2")"
      printf 'GOCLAW_TELEGRAM_TOKEN=%s\n' "$(cat "$3")"
      printf 'GOCLAW_OPENROUTER_API_KEY=%s\n' "$(cat "$4")"
      printf 'GROCY_API_KEY=%s\n' "$(cat "$5")"
    } > "$env_path"
  '';
in
{
  imports = [ ../modules/goclaw.nix ];

  # ---------------------------------------------------------------------------
  # GoClaw options — Telegram channel, OpenRouter provider, NixOS paths
  # ---------------------------------------------------------------------------

  services.goclaw = {
    enable = true;
    port = 18789;
    uiPort = 18780;
    stateDir = "/data/state-store/goclaw";
    logsDir = "/var/log/goclaw";
    postgresDSN = "postgres://goclaw@/goclaw?host=/run/postgresql";

    config = {
      channels.telegram = {
        enabled = true;
        dm_policy = "allowlist";
        allow_from = [ 560918177 ];
      };
      agents.defaults = {
        provider = "openai-codex";
        model = "gpt-5.3-codex";
      };
      tools.mcp_servers.grocy = {
        transport = "stdio";
        command = "${grocyMcp}/bin/grocy-mcp";
        env = {
          GROCY_BASE_URL = "http://127.0.0.1:2383";
        };
      };
    };

    environment = {
      GOCLAW_PROVIDER = "openai-codex";
      GOCLAW_MODEL = "gpt-5.3-codex";
      ROD_BROWSER_BIN = "${pkgs.chromium}/bin/chromium";
    };

    secrets = [
      "goclaw_gateway_token"
      "goclaw_encryption_key"
      "goclaw_telegram_token"
      "goclaw_openrouter_key"
      "goclaw_grocy_api_key"
    ];

    extraSkillPaths = [
      { name = "summarize"; path = "${steipeteTools}/tools/summarize/skills/summarize"; }
      { name = "gog";       path = "${steipeteTools}/tools/gogcli/skills/gog"; }
      { name = "goplaces";  path = "${steipeteTools}/tools/goplaces/skills/goplaces"; }
      { name = "camsnap";   path = "${steipeteTools}/tools/camsnap/skills/camsnap"; }
      { name = "sag";       path = "${steipeteTools}/tools/sag/skills/sag"; }
      { name = "sonoscli";  path = "${steipeteTools}/tools/sonoscli/skills/sonoscli"; }
      { name = "xuezh";     path = "${inputs.xuezh}/skills/xuezh"; }
      { name = "grocy";     path = ./skills/grocy; }
    ];

    webUi.enable = true;
  };

  # ---------------------------------------------------------------------------
  # sops secret ownership — NixOS-specific (owner/group/restartUnits)
  # ---------------------------------------------------------------------------

  sops.secrets."goclaw_gateway_token" = lib.mkForce {
    owner = "goclaw"; group = "goclaw"; mode = "0400";
    restartUnits = [ "goclaw.service" ];
  };
  sops.secrets."goclaw_encryption_key" = lib.mkForce {
    owner = "goclaw"; group = "goclaw"; mode = "0400";
    restartUnits = [ "goclaw.service" ];
  };
  sops.secrets."goclaw_telegram_token" = lib.mkForce {
    owner = "goclaw"; group = "goclaw"; mode = "0400";
    restartUnits = [ "goclaw.service" ];
  };
  sops.secrets."goclaw_openrouter_key" = lib.mkForce {
    owner = "goclaw"; group = "goclaw"; mode = "0400";
    restartUnits = [ "goclaw.service" ];
  };
  sops.secrets."goclaw_grocy_api_key" = lib.mkForce {
    owner = "goclaw"; group = "goclaw"; mode = "0400";
    restartUnits = [ "goclaw.service" ];
  };

  # ---------------------------------------------------------------------------
  # System user
  # ---------------------------------------------------------------------------

  users.users.goclaw = {
    isSystemUser = true;
    group = "goclaw";
    home = cfg.stateDir;
  };
  users.groups.goclaw = {};

  # ---------------------------------------------------------------------------
  # PostgreSQL database + role
  # ---------------------------------------------------------------------------

  services.postgresql.ensureDatabases = [ "goclaw" ];
  services.postgresql.ensureUsers = [{
    name = "goclaw";
    ensureDBOwnership = true;
  }];
  services.postgresql.authentication = lib.mkAfter ''
    local goclaw goclaw peer
  '';

  # ---------------------------------------------------------------------------
  # Systemd service
  # ---------------------------------------------------------------------------

  systemd.services.goclaw = {
    description = "GoClaw AI gateway";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "postgresql.service" ];
    wants = [ "network-online.target" ];
    requires = [ "postgresql.service" ];

    path = [ goclawPkg xuezhPkg pkgs.chromium pkgs.curl pkgs."claude-code" ];

    environment = cfg._commonEnv;

    serviceConfig = {
      Type = "simple";
      User = "goclaw";
      Group = "goclaw";
      ExecStartPre = [
        # Create pgcrypto + pgvector extensions (requires superuser)
        "+${pkgs.writeShellScript "goclaw-ensure-extensions" ''
          ${pkgs.util-linux}/bin/runuser -u postgres -- ${config.services.postgresql.package}/bin/psql -d goclaw -c 'CREATE EXTENSION IF NOT EXISTS "pgcrypto";'
          ${pkgs.util-linux}/bin/runuser -u postgres -- ${config.services.postgresql.package}/bin/psql -d goclaw -c 'CREATE EXTENSION IF NOT EXISTS "vector";'
        ''}"
        "${prepareEnv} ${config.sops.secrets.goclaw_gateway_token.path} ${config.sops.secrets.goclaw_encryption_key.path} ${config.sops.secrets.goclaw_telegram_token.path} ${config.sops.secrets.goclaw_openrouter_key.path} ${config.sops.secrets.goclaw_grocy_api_key.path}"
        "+${pkgs.writeShellScript "goclaw-prepare-state-chown" ''
          ${cfg._prepareState}
          ${pkgs.coreutils}/bin/chown -R goclaw:goclaw ${cfg.stateDir}
        ''}"
      ];
      ExecStart = "${goclawPkg}/bin/goclaw";
      EnvironmentFile = [ "-/run/goclaw/env" ];
      WorkingDirectory = cfg.stateDir;
      Restart = "on-failure";
      RestartSec = 10;

      # Sandboxing — Go binary has no JIT, but Chromium (browser tool) does
      DynamicUser = false;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      MemoryDenyWriteExecute = false; # Chromium V8 JIT needs W+X
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX AF_NETLINK";
      RestrictNamespaces = true;
      RestrictRealtime = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      CapabilityBoundingSet = "";
      RuntimeDirectory = "goclaw";
      RuntimeDirectoryMode = "0750";
      ReadWritePaths = [ cfg.stateDir ];
      Slice = "goclaw.slice";

      MemoryMax = "1G";
      CPUQuota = "200%";
    };
  };

  # ---------------------------------------------------------------------------
  # Web UI — nginx serves SPA + proxies API/WS, Traefik fronts with TLS
  # ---------------------------------------------------------------------------

  services.nginx.virtualHosts."goclaw.koch.brians.skin" = {
    listen = [{ addr = "127.0.0.1"; port = cfg.uiPort; }];
    root = "${cfg.uiPackage}/share/goclaw-ui";

    locations."/" = {
      tryFiles = "$uri $uri/ /index.html";
    };

    locations."/assets/" = {
      extraConfig = ''
        expires 1y;
        add_header Cache-Control "public, immutable";
      '';
    };

    locations."/ws" = {
      proxyPass = "http://127.0.0.1:${toString cfg.port}";
      proxyWebsockets = true;
    };

    locations."/v1/" = {
      proxyPass = "http://127.0.0.1:${toString cfg.port}";
    };

    locations."/health" = {
      proxyPass = "http://127.0.0.1:${toString cfg.port}";
    };
  };

  services.traefik.dynamicConfigOptions.http.routers.goclaw = {
    rule = "Host(`goclaw.koch.brians.skin`)";
    service = "goclaw";
    tls.certResolver = "desec";
  };
  services.traefik.dynamicConfigOptions.http.services.goclaw.loadBalancer.servers = [
    { url = "http://localhost:${toString cfg.uiPort}"; }
  ];

  systemd.slices.goclaw = {
    description = "GoClaw isolated slice";
    sliceConfig = {
      MemoryMax = "2G";
      CPUQuota = "200%";
    };
  };
}
