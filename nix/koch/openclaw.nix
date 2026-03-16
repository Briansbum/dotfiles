{ config, pkgs, inputs, lib, ... }:

let
  openclawPkg = inputs.nix-openclaw.packages.${pkgs.system}.openclaw;
  xuezhPkg = inputs.xuezh.packages.${pkgs.system}.default;
  steipeteTools = inputs.nix-openclaw.inputs.nix-steipete-tools;
  unitName = "nix-openclaw";
  stateDir = "/data/state-store/openclaw";

  # Collect all skill directories into a single nix store path
  skillsDir = pkgs.linkFarm "openclaw-skills" [
    { name = "summarize"; path = "${steipeteTools}/tools/summarize/skills/summarize"; }
    { name = "gog";       path = "${steipeteTools}/tools/gogcli/skills/gog"; }
    { name = "goplaces";  path = "${steipeteTools}/tools/goplaces/skills/goplaces"; }
    { name = "camsnap";   path = "${steipeteTools}/tools/camsnap/skills/camsnap"; }
    { name = "sag";       path = "${steipeteTools}/tools/sag/skills/sag"; }
    { name = "sonoscli";  path = "${steipeteTools}/tools/sonoscli/skills/sonoscli"; }
    { name = "xuezh";     path = "${inputs.xuezh}/skills/xuezh"; }
  ];

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

  # Runs as root (+ prefix) to copy skills from nix store into btrfs state
  installSkills = pkgs.writeShellScript "install-openclaw-skills" ''
    set -euo pipefail
    target="${stateDir}/skills"
    ${pkgs.coreutils}/bin/mkdir -p "$target"
    for skill in ${skillsDir}/*; do
      name=$(${pkgs.coreutils}/bin/basename "$skill")
      ${pkgs.coreutils}/bin/rm -rf "$target/$name"
      ${pkgs.coreutils}/bin/cp -rL "$skill" "$target/$name"
    done
    ${pkgs.coreutils}/bin/chmod -R u+rw "$target"
    ${pkgs.coreutils}/bin/chown -R openclaw:openclaw "$target"
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
    stateDir = stateDir;
    workingDirectory = stateDir;
    restart = "on-failure";
    restartSec = 10;
    config = {
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
    servicePath = [ openclawPkg xuezhPkg ];
    execStartPre = [
      "${prepareEnv} ${config.sops.secrets.openclaw_gateway_token.path} ${config.sops.secrets.openclaw_openrouter_key.path} ${config.sops.secrets.openclaw_telegram_token.path}"
      "+${installSkills}"
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
      ReadWritePaths = [ stateDir ];
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
