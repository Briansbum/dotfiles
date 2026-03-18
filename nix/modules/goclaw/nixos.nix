# GoClaw NixOS implementation — systemd service, NixOS PostgreSQL, nginx.
#
# Handles: system user, database provisioning, extension creation,
# secret env preparation, state directory ownership, systemd sandboxing,
# and nginx virtual host for the web dashboard.

{ config, pkgs, lib, ... }:

let
  cfg = config.services.goclaw;

  secretNames = lib.unique (lib.attrValues cfg.secretEnvironment);
  user = "goclaw";
  group = "goclaw";

  prepareEnv = pkgs.writeShellScript "goclaw-prepare-env" ''
    set -euo pipefail
    env_path="/run/goclaw/env"
    umask 077
    {
      ${lib.concatStringsSep "\n    " (lib.mapAttrsToList (envVar: secretName:
        "printf '${envVar}=%s\\n' \"$(cat ${config.sops.secrets.${secretName}.path})\""
      ) cfg.secretEnvironment)}
    } > "$env_path"
  '';
in
{
  imports = [ ./default.nix ];

  config = lib.mkIf cfg.enable {
    # -----------------------------------------------------------------------
    # sops secrets — with NixOS ownership and restart triggers
    # -----------------------------------------------------------------------

    sops.secrets = lib.listToAttrs (map (name: {
      inherit name;
      value = {
        owner = user;
        inherit group;
        mode = "0400";
        restartUnits = [ "goclaw.service" ];
      };
    }) secretNames);

    # -----------------------------------------------------------------------
    # System user
    # -----------------------------------------------------------------------

    users.users.${user} = {
      isSystemUser = true;
      inherit group;
      home = cfg.stateDir;
    };
    users.groups.${group} = {};

    # -----------------------------------------------------------------------
    # PostgreSQL — database, role, peer auth
    # -----------------------------------------------------------------------

    services.postgresql.ensureDatabases = [ "goclaw" ];
    services.postgresql.ensureUsers = [{
      name = user;
      ensureDBOwnership = true;
    }];
    services.postgresql.authentication = lib.mkAfter ''
      local goclaw ${user} peer
    '';

    # -----------------------------------------------------------------------
    # Systemd service
    # -----------------------------------------------------------------------

    systemd.services.goclaw = {
      description = "GoClaw AI gateway";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      requires = [ "postgresql.service" ];

      path = [ cfg.package pkgs.curl pkgs.claude-code ];
      environment = cfg._commonEnv;

      serviceConfig = {
        Type = "simple";
        User = user;
        Group = group;
        ExecStartPre = [
          # Extensions require superuser — run as postgres via + prefix
          "+${pkgs.writeShellScript "goclaw-ensure-extensions" ''
            ${pkgs.util-linux}/bin/runuser -u postgres -- ${config.services.postgresql.package}/bin/psql -d goclaw -c 'CREATE EXTENSION IF NOT EXISTS "pgcrypto";'
            ${pkgs.util-linux}/bin/runuser -u postgres -- ${config.services.postgresql.package}/bin/psql -d goclaw -c 'CREATE EXTENSION IF NOT EXISTS "vector";'
          ''}"
          "${prepareEnv}"
          "+${pkgs.writeShellScript "goclaw-prepare-state-chown" ''
            ${cfg._prepareState}
            ${pkgs.coreutils}/bin/chown -R ${user}:${group} ${cfg.stateDir}
          ''}"
        ];
        ExecStart = "${cfg.package}/bin/goclaw";
        EnvironmentFile = [ "-/run/goclaw/env" ];
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = 10;

        # Sandboxing
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

    systemd.slices.goclaw = {
      description = "GoClaw isolated slice";
      sliceConfig = {
        MemoryMax = "2G";
        CPUQuota = "200%";
      };
    };

    # -----------------------------------------------------------------------
    # Web UI — nginx virtual host (fronted by Traefik in host config)
    # -----------------------------------------------------------------------

    services.nginx.virtualHosts.${cfg.webUi.hostName} = lib.mkIf cfg.webUi.enable {
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
  };
}
