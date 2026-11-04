# Host-side runners for koch's rootless QEMU/KVM service VMs.
{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
let
  vmNames = [ "chorcy" "grocy" "immich" "syncthing" "git" "knot" ];
  vmCfg = name: inputs.self.nixosConfigurations."koch-${name}".config;
  publishedPorts = name:
    map (p: if p.hostPort == null then p.guestPort else p.hostPort)
      (lib.filter (p: p.bind == "all-interfaces" && p.proto == "tcp") (vmCfg name).koch-vm.ports);
  mkVmUnit = name: {
    "koch-vm-${name}" = {
      description = "koch ${name} service VM (rootless qemu)";
      # Some guests consume secrets staged by tmpfiles from sops-nix.  The VM
      # must not win the boot race and start with a missing/host-only secret.
      after = [
        "network-online.target"
        "systemd-tmpfiles-setup.service"
        "sops-nix.service"
        "koch-vm-stage-secrets.service"
      ];
      requires = [ "koch-vm-stage-secrets.service" ];
      wants = [
        "network-online.target"
        "systemd-tmpfiles-setup.service"
        "sops-nix.service"
      ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        NIX_DISK_IMAGE = "/data/state-store/vm/${name}/disk.qcow2";
        HOME = config.users.users.alex.home;
      };
      serviceConfig = {
        User = "alex";
        Group = "users";
        WorkingDirectory = "/data/state-store/vm/${name}";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /data/state-store/vm/${name}";
        ExecStart = "${(vmCfg name).system.build.vm}/bin/run-koch-${name}-vm";
        Restart = "on-failure";
        RestartSec = 10;
        NoNewPrivileges = true;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
in
{
  sops.secrets."syncthing_cert".sopsFile = ../syncthing.yaml;
  sops.secrets."syncthing_key".sopsFile = ../syncthing.yaml;
  systemd.services = lib.mkMerge (
    (map mkVmUnit vmNames)
    ++ [
      {
        # sops-nix deliberately makes secret paths root-readable only. Stage
        # regular files in the VM shares as root, then let the rootless QEMU
        # units consume them. A tmpfiles C+ rule cannot replace the old
        # absolute symlink, which is why this is an explicit oneshot.
        koch-vm-stage-secrets = {
          description = "Stage secrets for koch service VMs";
          wantedBy = [ "multi-user.target" ];
          after = [ "sops-nix.service" "systemd-tmpfiles-setup.service" ];
          wants = [ "sops-nix.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            rm -f /var/lib/koch-vm/syncthing/cert.pem /var/lib/koch-vm/syncthing/key.pem
            install -m 640 ${config.sops.secrets.syncthing_cert.path} /var/lib/koch-vm/syncthing/cert.pem
            install -m 640 ${config.sops.secrets.syncthing_key.path} /var/lib/koch-vm/syncthing/key.pem
            chown alex:users /var/lib/koch-vm/syncthing/cert.pem /var/lib/koch-vm/syncthing/key.pem
            rm -f /var/lib/koch-vm/immich/alloy-pg-password
            install -m 640 ${config.sops.secrets.immich_alloy_pg_password.path} /var/lib/koch-vm/immich/alloy-pg-password
            chown alex:users /var/lib/koch-vm/immich/alloy-pg-password
          '';
        };
      }
    ]
  );
  networking.firewall.allowedTCPPorts = lib.unique (lib.flatten (map publishedPorts vmNames));
  users.groups.git = { };
  users.users.alex.extraGroups = [ "kvm" "git" ];
  systemd.tmpfiles.rules = [
    "d /var/lib/koch-vm/syncthing 0700 alex users -"
    "d /var/lib/koch-vm/immich 0700 alex users -"
    "d /data/state-store/vm 0755 alex users -"
    "d /data/state-store/git 0755 alex users -"
  ]
    ++ map (name: "d /data/state-store/vm/${name} 0755 alex users -") vmNames;
}
