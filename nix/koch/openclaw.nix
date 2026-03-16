{ config, pkgs, inputs, lib, ... }:

let
  openclawPkg = inputs.nix-openclaw.packages.${pkgs.system}.openclaw;
  prepareEnvScript = ./openclaw/prepare-openclaw-env.sh;
  unitName = "nix-openclaw";
in
{
  imports = [
    inputs.nix-openclaw.nixosModules.openclaw-gateway
  ];

  # nix-openclaw secret values - each secret is stored in secrets.yaml as key-value pairs
  # openclaw_gateway_token: ENC[AES256_GCM,data:YOUR_ENCRYPTED_TOKEN,iv:RANDOM_IV,tag:TAG,type:str]
  # openclaw_telegram_token: ENC[AES256_GCM,data:YOUR_ENCRYPTED_TELEGRAM_TOKEN,iv:RANDOM_IV,tag:TAG,type:str]
  # openclaw_openrouter_key: ENC[AES256_GCM,data:YOUR_ENCRYPTED_OPENROUTER_KEY,iv:RANDOM_IV,tag:TAG,type:str]
  sops.secrets."openclaw_gateway_token" = {
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
    restartUnits = [ "nix-openclaw.service" ];
  };
  sops.secrets."openclaw_telegram_token" = {
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
    restartUnits = [ "nix-openclaw.service" ];
  };
  sops.secrets."openclaw_openrouter_key" = {
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
    restartUnits = [ "nix-openclaw.service" ];
  };

  services.openclaw-gateway = {
    enable = true;
    unitName = unitName;
    package = openclawPkg;
    stateDir = "/var/lib/openclaw";
    workingDirectory = "/var/lib/openclaw";
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
        # -1001234567890   # couples group (no @mention required)
        ];
      # Example group configs:
      #    groups = {
      #      "*" = { requireMention = true; };
      #      "-1001234567890" = { requireMention = false; }; # couples group
      #      "-1002345678901" = { requireMention = true; };  # noisy group
      #    };
      };
    };
    environment = {
      # Don't expose any ports - external comms only
      OPENCLAW_NO_SERVER = "1";
    };
    environmentFiles = [ "-/run/openclaw/env" ];
    execStartPre = [
      "${prepareEnvScript} ${config.sops.secrets.openclaw_gateway_token.path} ${config.sops.secrets.openclaw_openrouter_key.path} ${config.sops.secrets.openclaw_telegram_token.path}"
    ];
  };

  systemd.services.${unitName} = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      # Run as dedicated user with minimal privileges
      DynamicUser = false;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      MemoryDenyWriteExecute = false;
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

      # Resource limits
      MemoryMax = "2G";
      CPUQuota = "200%";

      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce "10s";
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
