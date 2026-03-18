# Shared GoClaw options and config generation.
#
# Platform implementations live in nixos.nix and darwin.nix.
# Host files import the appropriate platform module and set these options.

{ config, pkgs, lib, ... }:

let
  cfg = config.services.goclaw;
in
{
  options.services.goclaw = {
    enable = lib.mkEnableOption "GoClaw AI gateway";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.goclaw;
      description = "The goclaw gateway package.";
    };

    uiPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.goclaw-ui;
      description = "The goclaw web dashboard package.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 18790;
      description = "Gateway listen port.";
    };

    uiPort = lib.mkOption {
      type = lib.types.port;
      default = 18780;
      description = "Web dashboard listen port.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      description = "Writable directory for config, skills, and workspace.";
    };

    logsDir = lib.mkOption {
      type = lib.types.str;
      description = "Log file directory.";
    };

    postgresDSN = lib.mkOption {
      type = lib.types.str;
      description = "PostgreSQL connection string.";
    };

    config = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "GoClaw config.json content (channels, agents, MCP servers, etc).";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables for the goclaw process.";
    };

    secretEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = ''
        Mapping of environment variable name to sops secret name.
        Platform modules use this to wire secrets into the process environment.
      '';
      example = {
        GOCLAW_GATEWAY_TOKEN = "goclaw_gateway_token";
        GOCLAW_ENCRYPTION_KEY = "goclaw_encryption_key";
      };
    };

    extraSkillPaths = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "Extra skill paths for linkFarm: [{ name = \"...\"; path = \"...\"; }].";
    };

    webUi = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Serve the goclaw web dashboard via nginx.";
      };

      hostName = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "Server name for the nginx virtual host.";
      };
    };

    # Internal derivations — computed from options, consumed by platform modules.
    _configJson = lib.mkOption { type = lib.types.package; internal = true; readOnly = true; };
    _skillsDir = lib.mkOption { type = lib.types.nullOr lib.types.package; internal = true; readOnly = true; };
    _prepareState = lib.mkOption { type = lib.types.package; internal = true; readOnly = true; };
    _commonEnv = lib.mkOption { type = lib.types.attrsOf lib.types.str; internal = true; readOnly = true; };
    _nginxConf = lib.mkOption { type = lib.types.nullOr lib.types.package; internal = true; readOnly = true; };
  };

  config = lib.mkIf cfg.enable {
    services.goclaw._configJson = pkgs.writeText "goclaw-config.json" (builtins.toJSON ({
      gateway = { host = "127.0.0.1"; port = cfg.port; };
    } // cfg.config));

    services.goclaw._skillsDir =
      if cfg.extraSkillPaths != []
      then pkgs.linkFarm "goclaw-skills" cfg.extraSkillPaths
      else null;

    services.goclaw._prepareState = pkgs.writeShellScript "goclaw-prepare-state" ''
      set -euo pipefail

      ${pkgs.coreutils}/bin/mkdir -p "${cfg.stateDir}/config" "${cfg.stateDir}/workspace" "${cfg.stateDir}/skills" "${cfg.logsDir}"

      # Copy config to writable location (goclaw writes runtime state into it)
      ${pkgs.coreutils}/bin/cp -f ${cfg._configJson} "${cfg.stateDir}/config/goclaw.json"
      ${pkgs.coreutils}/bin/chmod 0640 "${cfg.stateDir}/config/goclaw.json"

      # Copy bundled skills from nix store into writable directory
      for skill in ${cfg.package}/share/goclaw/skills/*; do
        name=$(${pkgs.coreutils}/bin/basename "$skill")
        ${pkgs.coreutils}/bin/rm -rf "${cfg.stateDir}/skills/$name"
        ${pkgs.coreutils}/bin/cp -rL "$skill" "${cfg.stateDir}/skills/$name"
      done
      ${lib.optionalString (cfg._skillsDir != null) ''
        for skill in ${cfg._skillsDir}/*; do
          name=$(${pkgs.coreutils}/bin/basename "$skill")
          ${pkgs.coreutils}/bin/rm -rf "${cfg.stateDir}/skills/$name"
          ${pkgs.coreutils}/bin/cp -rL "$skill" "${cfg.stateDir}/skills/$name"
        done
      ''}
      ${pkgs.coreutils}/bin/chmod -R u+rw "${cfg.stateDir}/skills"
    '';

    services.goclaw._commonEnv = {
      GOCLAW_HOST = "127.0.0.1";
      GOCLAW_PORT = toString cfg.port;
      GOCLAW_DATA_DIR = cfg.stateDir;
      GOCLAW_CONFIG = "${cfg.stateDir}/config/goclaw.json";
      GOCLAW_MIGRATIONS_DIR = "${cfg.package}/share/goclaw/migrations";
      GOCLAW_BUNDLED_SKILLS_DIR = "${cfg.package}/share/goclaw/skills";
      GOCLAW_SKILLS_DIR = "${cfg.stateDir}/skills";
      GOCLAW_AUTO_UPGRADE = "true";
      GOCLAW_TELEMETRY_ENABLED = "false";
      GOCLAW_POSTGRES_DSN = cfg.postgresDSN;
      GOCLAW_CLAUDE_CLI_PATH = "${pkgs.claude-code}/bin/claude";
      GOCLAW_CLAUDE_CLI_WORK_DIR = "${cfg.stateDir}/workspace";
    } // cfg.environment;

    services.goclaw._nginxConf =
      if cfg.webUi.enable then
        pkgs.writeText "goclaw-nginx.conf" ''
          worker_processes 1;
          daemon off;
          pid ${cfg.stateDir}/nginx.pid;
          error_log ${cfg.logsDir}/nginx-error.log warn;

          events { worker_connections 64; }

          http {
            include ${pkgs.nginx}/conf/mime.types;
            default_type application/octet-stream;
            access_log ${cfg.logsDir}/nginx-access.log;

            server {
              listen 127.0.0.1:${toString cfg.uiPort};
              server_name ${cfg.webUi.hostName};
              root ${cfg.uiPackage}/share/goclaw-ui;

              location / {
                try_files $uri $uri/ /index.html;
              }

              location /assets/ {
                expires 1y;
                add_header Cache-Control "public, immutable";
              }

              location /ws {
                proxy_pass http://127.0.0.1:${toString cfg.port};
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
                proxy_set_header Host $host;
              }

              location /v1/ {
                proxy_pass http://127.0.0.1:${toString cfg.port};
              }

              location /health {
                proxy_pass http://127.0.0.1:${toString cfg.port};
              }
            }
          }
        ''
      else null;
  };
}
