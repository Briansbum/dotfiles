# Host transport only: guest service modules own producing recoverable material.
{ inputs, vmNames }:
{ config, lib, pkgs, ... }:
let
  cfg = config.koch-vm-backups;
  backup = name: inputs.self.nixosConfigurations."koch-${name}".config.koch-vm.backup;
  enabled = lib.filter (name: (backup name).enable) vmNames;
  staged = lib.filter (name: builtins.elem (backup name).hostDirectory (backup name).paths) enabled;
  manifest = builtins.listToAttrs (map (name: {
    inherit name;
    value = {
      inherit (backup name) paths requiredMounts requiredPaths freshnessFile maxAgeSeconds;
    };
  }) enabled);
  manifests = pkgs.writeText "koch-vm-backup-manifest.json" (builtins.toJSON manifest);
in {
  options.koch-vm-backups = {
    enable = lib.mkEnableOption "offsite restic transport for registered VM backup sources";
    repository = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Restic repository URL. Must be initialized explicitly before the first run.";
    };
    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime path to the restic password; never put the password in Nix.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime systemd EnvironmentFile containing storage credentials.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [ {
        assertion = !cfg.enable || (cfg.repository != null && cfg.passwordFile != null);
        message = "koch-vm-backups requires repository and passwordFile when enabled.";
      } ];
      warnings = lib.optional (!cfg.enable && enabled != [ ])
        "VM backup staging is enabled, but koch-vm-backups.enable is false: no offsite VM backups will run.";
      environment.etc."koch-vm-backups.json".source = manifests;
      # QEMU/virtiofsd runs as alex:users. Guest producers must have matching
      # access to their mount (currently UID 1000 for Grocy).
      systemd.tmpfiles.rules = map (name:
        "d ${(backup name).hostDirectory} 0700 alex users -") staged;
    }
    (lib.mkIf cfg.enable {
      services.restic.backups = builtins.listToAttrs (map (name: {
        name = "koch-vm-${name}";
        value = {
          inherit (cfg) repository passwordFile environmentFile;
          inherit (backup name) paths;
          # No automatic init, forget, prune, or policy changes.
          initialize = false;
          exclude = [ ".backup-tmp-*" ] ++ (backup name).exclude;
          extraBackupArgs = [ "--tag" "koch-vm:${name}" ];
          timerConfig = {
            OnCalendar = "*-*-* 03:00:00";
            RandomizedDelaySec = "30m";
            Persistent = true;
          };
          backupPrepareCommand = ''
            #!${pkgs.runtimeShell}
            set -eu
            ${pkgs.python3}/bin/python3 ${./check-backup.py} ${manifests} ${lib.escapeShellArg name}
          '';
        };
      }) enabled);
    })
  ];
}
