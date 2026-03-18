# Shared GoClaw module — options + platform-agnostic config generation.
#
# Imported by both koch (NixOS/systemd) and Alexs-MacBook-Pro (nix-darwin/launchd).
# Each host sets the options below and provides its own service/postgres/web plumbing.

{ config, pkgs, lib, ... }:

let
  cfg = config.services.goclaw;
  goclawPkg = cfg.package;
  goclawUi = cfg.uiPackage;
in
{
  options.services.goclaw = {
    enable = lib.mkEnableOption "GoClaw AI gateway";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.goclaw;
      description = "The goclaw package.";
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
      default = "/var/log/goclaw";
      description = "Log directory.";
    };

    postgresDSN = lib.mkOption {
      type = lib.types.str;
      description = "PostgreSQL connection string.";
    };

    config = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "GoClaw config.json content (channel config, agent defaults, MCP servers, etc).";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables passed to goclaw.";
    };

    secrets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "sops secret names to declare.";
    };

    secretEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Mapping of env var name → sops secret name. Wrapper reads these at launch.";
    };

    extraSkillPaths = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "Extra skill paths for linkFarm: [{ name = \"...\"; path = \"...\"; }].";
    };

    webUi.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Serve the goclaw web dashboard.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Expose generated derivations as internal options so host modules can use them
    services.goclaw._configJson = pkgs.writeText "goclaw-config.json" (builtins.toJSON ({
      gateway = {
        host = "127.0.0.1";
        port = cfg.port;
      };
    } // cfg.config));

    services.goclaw._skillsDir = lib.mkIf (cfg.extraSkillPaths != []) (
      pkgs.linkFarm "goclaw-skills" cfg.extraSkillPaths
    );

    services.goclaw._prepareState = pkgs.writeShellScript "goclaw-prepare-state" ''
      set -euo pipefail

      mkdir -p "${cfg.stateDir}/config" "${cfg.stateDir}/workspace" "${cfg.stateDir}/skills" "${cfg.logsDir}"

      # Copy config to writable location (goclaw writes runtime state into it)
      cp -f ${cfg._configJson} "${cfg.stateDir}/config/goclaw.json"
      chmod 0640 "${cfg.stateDir}/config/goclaw.json"

      # Copy bundled skills from nix store into writable directory
      for skill in ${goclawPkg}/share/goclaw/skills/*; do
        name=$(basename "$skill")
        rm -rf "${cfg.stateDir}/skills/$name"
        cp -rL "$skill" "${cfg.stateDir}/skills/$name"
      done
      ${lib.optionalString (cfg.extraSkillPaths != []) ''
        # Copy extra skills from linkFarm
        for skill in ${cfg._skillsDir}/*; do
          name=$(basename "$skill")
          rm -rf "${cfg.stateDir}/skills/$name"
          cp -rL "$skill" "${cfg.stateDir}/skills/$name"
        done
      ''}
      chmod -R u+rw "${cfg.stateDir}/skills"
    '';

    services.goclaw._commonEnv = {
      GOCLAW_HOST = "127.0.0.1";
      GOCLAW_PORT = toString cfg.port;
      GOCLAW_DATA_DIR = cfg.stateDir;
      GOCLAW_CONFIG = "${cfg.stateDir}/config/goclaw.json";
      GOCLAW_MIGRATIONS_DIR = "${goclawPkg}/share/goclaw/migrations";
      GOCLAW_BUNDLED_SKILLS_DIR = "${goclawPkg}/share/goclaw/skills";
      GOCLAW_SKILLS_DIR = "${cfg.stateDir}/skills";
      GOCLAW_AUTO_UPGRADE = "true";
      GOCLAW_TELEMETRY_ENABLED = "false";
      GOCLAW_POSTGRES_DSN = cfg.postgresDSN;
      GOCLAW_CLAUDE_CLI_PATH = "${pkgs.claude-code}/bin/claude";
      GOCLAW_CLAUDE_CLI_WORK_DIR = "${cfg.stateDir}/workspace";
    } // cfg.environment;

    services.goclaw._nginxConf = lib.mkIf cfg.webUi.enable (
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
            root ${goclawUi}/share/goclaw-ui;

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
    );

    # Declare sops secrets for all entries in cfg.secrets
    sops.secrets = lib.listToAttrs (map (name: {
      inherit name;
      value = {};
    }) cfg.secrets);
  };

  # Internal options — not for users, consumed by host modules
  options.services.goclaw._configJson = lib.mkOption { type = lib.types.package; internal = true; };
  options.services.goclaw._skillsDir = lib.mkOption { type = lib.types.anything; internal = true; default = null; };
  options.services.goclaw._prepareState = lib.mkOption { type = lib.types.package; internal = true; };
  options.services.goclaw._commonEnv = lib.mkOption { type = lib.types.attrsOf lib.types.str; internal = true; };
  options.services.goclaw._nginxConf = lib.mkOption { type = lib.types.anything; internal = true; default = null; };
}
