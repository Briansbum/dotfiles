# Recipe Import NixOS module — OCI container, systemd-managed via docker.
#
# Follows the same pattern as goclaw/nixos.nix:
#   - Self-contained layered OCI image built by Nix (no /nix/store bind-mount)
#   - Pre-start oneshot writes secrets to /run/recipe-import/env
#   - Container reads env file; data volume bind-mounted from host

{ config, pkgs, lib, ... }:

let
  cfg = config.services.recipe-import;

  containerImage = pkgs.dockerTools.buildLayeredImage {
    name = "recipe-import";
    tag  = "latest";

    contents = [
      cfg.package
      pkgs.nodejs_22
      pkgs.claude-code
      pkgs.bash
      pkgs.coreutils
      pkgs.cacert
    ];

    fakeRootCommands = ''
      mkdir -p /data /tmp
      chmod 1777 /tmp
      printf 'root:x:0:0:root:/root:/bin/sh\nrecipe-import:x:${toString cfg.uid}:${toString cfg.gid}::/data:/bin/bash\nnobody:x:65534:65534:nobody:/:/bin/false\n' \
        > /etc/passwd
      printf 'root:x:0:\nrecipe-import:x:${toString cfg.gid}:\nnobody:x:65534:\n' > /etc/group
      printf 'hosts: files dns\n' > /etc/nsswitch.conf
    '';
    enableFakechroot = true;

    config = {
      Entrypoint = [ "${pkgs.nodejs_22}/bin/node" "${cfg.package}/server.js" ];
      WorkingDir = "${cfg.package}";
      Env = [
        "NODE_ENV=production"
        "HOSTNAME=0.0.0.0"
        "PORT=3000"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
    };
  };

  prepareEnv = pkgs.writeShellScript "recipe-import-prepare-env" ''
    set -euo pipefail
    umask 077
    printf 'GROCY_API_KEY=%s\n' "$(cat ${config.sops.secrets.recipe_import_grocy_api_key.path})" \
      > /run/recipe-import/env
  '';
in
{
  options.services.recipe-import = {
    enable = lib.mkEnableOption "Recipe Import for Grocy";

    package = lib.mkOption {
      type        = lib.types.package;
      description = "The recipe-import Next.js package";
    };

    port = lib.mkOption {
      type    = lib.types.port;
      default = 3100;
      description = "Port exposed on 127.0.0.1 for Traefik";
    };

    dataDir = lib.mkOption {
      type    = lib.types.str;
      default = "/data/recipe-import";
      description = "Host path for SQLite DB and image uploads";
    };

    grocyBaseUrl = lib.mkOption {
      type    = lib.types.str;
      default = "http://host.docker.internal:2383";
      description = "Grocy URL reachable from inside the container";
    };

    uid = lib.mkOption { type = lib.types.int; default = 987; };
    gid = lib.mkOption { type = lib.types.int; default = 987; };
  };

  config = lib.mkIf cfg.enable {
    # -------------------------------------------------------------------------
    # sops secrets
    # -------------------------------------------------------------------------

    sops.secrets.recipe_import_grocy_api_key = {
      owner        = "root";
      mode         = "0400";
      restartUnits = [ "recipe-import-prepare.service" ];
    };

    # -------------------------------------------------------------------------
    # System user (host side — owns the data dir bind-mount)
    # -------------------------------------------------------------------------

    users.users.recipe-import = {
      uid          = cfg.uid;
      isSystemUser = true;
      group        = "recipe-import";
      home         = cfg.dataDir;
    };
    users.groups.recipe-import = { gid = cfg.gid; };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}         0750 recipe-import recipe-import -"
      "d ${cfg.dataDir}/uploads 0750 recipe-import recipe-import -"
    ];

    # -------------------------------------------------------------------------
    # Docker
    # -------------------------------------------------------------------------

    virtualisation.docker.enable = true;

    # -------------------------------------------------------------------------
    # Pre-start: chown data dir, write env file
    # -------------------------------------------------------------------------

    systemd.services.recipe-import-prepare = {
      description = "recipe-import pre-start preparation";
      wantedBy    = [ "multi-user.target" ];
      before      = [ "docker-recipe-import.service" ];

      serviceConfig = {
        Type                 = "oneshot";
        RemainAfterExit      = true;
        RuntimeDirectory     = "recipe-import";
        RuntimeDirectoryMode = "0750";

        ExecStart = pkgs.writeShellScript "recipe-import-prepare" ''
          set -euo pipefail
          ${pkgs.coreutils}/bin/chown -R ${toString cfg.uid}:${toString cfg.gid} ${cfg.dataDir}
          ${prepareEnv}
        '';
      };
    };

    systemd.services.docker-recipe-import = {
      after    = [ "recipe-import-prepare.service" ];
      requires = [ "recipe-import-prepare.service" ];
    };

    # -------------------------------------------------------------------------
    # OCI container
    # -------------------------------------------------------------------------

    virtualisation.oci-containers.backend = lib.mkDefault "docker";
    virtualisation.oci-containers.containers.recipe-import = {
      image     = "recipe-import:latest";
      imageFile = containerImage;

      environment = {
        GROCY_BASE_URL = cfg.grocyBaseUrl;
        DATA_DIR       = "/data";
        PORT           = "3000";
        CLAUDE_BIN     = "${pkgs.claude-code}/bin/claude";
        # claude -p reads auth from ~/.claude/; HOME is bound into the data volume
        # so credentials persist across container restarts.
        HOME           = "/data";
      };
      environmentFiles = [ "/run/recipe-import/env" ];

      volumes = [ "${cfg.dataDir}:/data:rw" ];

      extraOptions = [
        "--publish=127.0.0.1:${toString cfg.port}:3000"
        "--add-host=host.docker.internal:host-gateway"
      ];
    };
  };
}
