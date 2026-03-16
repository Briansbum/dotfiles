{ config, pkgs, inputs, lib, ... }:

let
  goclawPkg = pkgs.goclaw;
  xuezhPkg = inputs.xuezh.packages.${pkgs.system}.default;
  steipeteTools = inputs.nix-openclaw.inputs.nix-steipete-tools;
  stateDir = "/data/state-store/goclaw";

  # Collect all skill directories into a single nix store path
  skillsDir = pkgs.linkFarm "goclaw-skills" [
    { name = "summarize"; path = "${steipeteTools}/tools/summarize/skills/summarize"; }
    { name = "gog";       path = "${steipeteTools}/tools/gogcli/skills/gog"; }
    { name = "goplaces";  path = "${steipeteTools}/tools/goplaces/skills/goplaces"; }
    { name = "camsnap";   path = "${steipeteTools}/tools/camsnap/skills/camsnap"; }
    { name = "sag";       path = "${steipeteTools}/tools/sag/skills/sag"; }
    { name = "sonoscli";  path = "${steipeteTools}/tools/sonoscli/skills/sonoscli"; }
    { name = "xuezh";     path = "${inputs.xuezh}/skills/xuezh"; }
  ];

  configJson = pkgs.writeText "goclaw.json" (builtins.toJSON {
    channels.telegram = {
      enabled = true;
      dm_policy = "allowlist";
      allow_from = [ 560918177 ];
    };
    agents.defaults.model = "anthropic/claude-sonnet-4";
  });

  prepareEnv = pkgs.writeShellScript "prepare-goclaw-env" ''
    set -euo pipefail
    env_path="/run/goclaw/env"
    umask 077
    {
      printf 'GOCLAW_GATEWAY_TOKEN=%s\n' "$(cat "$1")"
      printf 'GOCLAW_ENCRYPTION_KEY=%s\n' "$(cat "$2")"
      printf 'GOCLAW_TELEGRAM_TOKEN=%s\n' "$(cat "$3")"
      printf 'GOCLAW_OPENROUTER_API_KEY=%s\n' "$(cat "$4")"
    } > "$env_path"
  '';

  prepareState = pkgs.writeShellScript "prepare-goclaw-state" ''
    set -euo pipefail

    # Ensure state directory exists
    ${pkgs.coreutils}/bin/mkdir -p "${stateDir}"
    ${pkgs.coreutils}/bin/chown goclaw:goclaw "${stateDir}"

    # Copy config to writable location
    ${pkgs.coreutils}/bin/mkdir -p "${stateDir}/config"
    ${pkgs.coreutils}/bin/cp -f ${configJson} "${stateDir}/config/goclaw.json"
    ${pkgs.coreutils}/bin/chown -R goclaw:goclaw "${stateDir}/config"
    ${pkgs.coreutils}/bin/chmod 0640 "${stateDir}/config/goclaw.json"

    # Copy skills from nix store into writable directory
    target="${stateDir}/skills"
    ${pkgs.coreutils}/bin/mkdir -p "$target"
    for skill in ${skillsDir}/*; do
      name=$(${pkgs.coreutils}/bin/basename "$skill")
      ${pkgs.coreutils}/bin/rm -rf "$target/$name"
      ${pkgs.coreutils}/bin/cp -rL "$skill" "$target/$name"
    done
    ${pkgs.coreutils}/bin/chmod -R u+rw "$target"
    ${pkgs.coreutils}/bin/chown -R goclaw:goclaw "$target"
  '';
in
{
  # -------------------------------------------------------------------------
  # Secrets
  # -------------------------------------------------------------------------

  sops.secrets."goclaw_gateway_token" = {
    owner = "goclaw";
    group = "goclaw";
    mode = "0400";
    restartUnits = [ "goclaw.service" ];
  };
  sops.secrets."goclaw_encryption_key" = {
    owner = "goclaw";
    group = "goclaw";
    mode = "0400";
    restartUnits = [ "goclaw.service" ];
  };
  sops.secrets."goclaw_telegram_token" = {
    owner = "goclaw";
    group = "goclaw";
    mode = "0400";
    restartUnits = [ "goclaw.service" ];
  };
  sops.secrets."goclaw_openrouter_key" = {
    owner = "goclaw";
    group = "goclaw";
    mode = "0400";
    restartUnits = [ "goclaw.service" ];
  };

  # -------------------------------------------------------------------------
  # System user
  # -------------------------------------------------------------------------

  users.users.goclaw = {
    isSystemUser = true;
    group = "goclaw";
    home = stateDir;
  };
  users.groups.goclaw = {};

  # -------------------------------------------------------------------------
  # PostgreSQL database + role
  # -------------------------------------------------------------------------

  services.postgresql.ensureDatabases = [ "goclaw" ];
  services.postgresql.ensureUsers = [{
    name = "goclaw";
    ensureDBOwnership = true;
  }];
  services.postgresql.authentication = lib.mkAfter ''
    local goclaw goclaw peer
  '';

  # -------------------------------------------------------------------------
  # Systemd service
  # -------------------------------------------------------------------------

  systemd.services.goclaw = {
    description = "GoClaw AI gateway";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "postgresql.service" ];
    wants = [ "network-online.target" ];
    requires = [ "postgresql.service" ];

    path = [ goclawPkg xuezhPkg ];

    environment = {
      GOCLAW_POSTGRES_DSN = "postgres://goclaw@/goclaw?host=/run/postgresql";
      GOCLAW_HOST = "127.0.0.1";
      GOCLAW_PORT = "18789";
      GOCLAW_DATA_DIR = stateDir;
      GOCLAW_CONFIG = "${stateDir}/config/goclaw.json";
      GOCLAW_MIGRATIONS_DIR = "${goclawPkg}/share/goclaw/migrations";
      GOCLAW_BUNDLED_SKILLS_DIR = "${goclawPkg}/share/goclaw/skills";
      GOCLAW_SKILLS_DIR = "${stateDir}/skills";
      GOCLAW_AUTO_UPGRADE = "true";
      GOCLAW_MODEL = "anthropic/claude-sonnet-4";
      GOCLAW_TELEMETRY_ENABLED = "false";
    };

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
        "${prepareEnv} ${config.sops.secrets.goclaw_gateway_token.path} ${config.sops.secrets.goclaw_encryption_key.path} ${config.sops.secrets.goclaw_telegram_token.path} ${config.sops.secrets.goclaw_openrouter_key.path}"
        "+${prepareState}"
      ];
      ExecStart = "${goclawPkg}/bin/goclaw";
      EnvironmentFile = [ "-/run/goclaw/env" ];
      WorkingDirectory = stateDir;
      Restart = "on-failure";
      RestartSec = 10;

      # Sandboxing — stricter than openclaw since Go has no JIT
      DynamicUser = false;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      MemoryDenyWriteExecute = true;
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
      ReadWritePaths = [ stateDir ];
      Slice = "goclaw.slice";

      MemoryMax = "1G";
      CPUQuota = "200%";
    };
  };

  systemd.slices.goclaw = {
    description = "GoClaw isolated slice";
    sliceConfig = {
      MemoryMax = "2G";
      CPUQuota = "200%";
    };
  };
}
