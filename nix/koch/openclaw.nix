{ config, pkgs, inputs, lib, ... }:

let
  openclawPkg = inputs.nix-openclaw.packages.${pkgs.system}.openclaw;
  unitName = "nix-openclaw";

  prepareEnv = pkgs.writeShellScript "prepare-openclaw-env" ''
    set -euo pipefail
    env_path="/run/openclaw/env"
    umask 077
    {
      printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$(cat "$1")"
      printf 'OPENAI_API_KEY=%s\n' "$(cat "$2")"
      printf 'OPENAI_API_BASE=https://openrouter.ai/api/v1\n'
      printf 'OPENCLAW_TELEGRAM_BOT_TOKEN=%s\n' "$(cat "$3")"
    } > "$env_path"
  '';
in
{
  imports = [
    inputs.nix-openclaw.nixosModules.openclaw-gateway
  ];

  sops.secrets."openclaw_gateway_token" = {
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
    restartUnits = [ "${unitName}.service" ];
  };
  sops.secrets."openclaw_telegram_token" = {
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
    restartUnits = [ "${unitName}.service" ];
  };
  sops.secrets."openclaw_openrouter_key" = {
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
    restartUnits = [ "${unitName}.service" ];
  };

  services.openclaw-gateway = {
    enable = true;
    unitName = unitName;
    package = openclawPkg;
    stateDir = "/var/lib/openclaw";
    workingDirectory = "/var/lib/openclaw";
    restart = "on-failure";
    restartSec = 10;
    config = {
      plugins = {
        enabled = true;
      };

      gateway = {
        mode = "local";
      };

      channels.telegram = {
        tokenFile = config.sops.secrets.openclaw_telegram_token.path;
        allowFrom = [
          560918177
        ];
      };
    };
    environment = {
      OPENCLAW_NO_SERVER = "1";
    };
    environmentFiles = [ "-/run/openclaw/env" ];
    execStartPre = [
      "${prepareEnv} ${config.sops.secrets.openclaw_gateway_token.path} ${config.sops.secrets.openclaw_openrouter_key.path} ${config.sops.secrets.openclaw_telegram_token.path}"
    ];
  };

  systemd.services.${unitName} = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      DynamicUser = false;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      MemoryDenyWriteExecute = false; # Node.js JIT requires W+X memory
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
      RuntimeDirectory = "openclaw";
      RuntimeDirectoryMode = "0750";
      StateDirectory = "openclaw";
      StateDirectoryMode = "0750";
      Slice = "openclaw.slice";

      MemoryMax = "2G";
      CPUQuota = "200%";
    };
  };

  systemd.slices.openclaw = {
    description = "OpenClaw isolated slice";
    sliceConfig = {
      MemoryMax = "32G";
      CPUQuota = "200%";
    };
  };
}
