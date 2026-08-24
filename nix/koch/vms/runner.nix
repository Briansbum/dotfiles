# Host-side runners for koch's rootless QEMU/KVM service VMs.
{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
let
  vmNames = [ "chorcy" "grocy" "immich" "syncthing" "git" ];
  vmCfg = name: inputs.self.nixosConfigurations."koch-${name}".config;
  publishedPorts = name:
    map (p: if p.hostPort == null then p.guestPort else p.hostPort)
      (lib.filter (p: p.bind == "all-interfaces" && p.proto == "tcp") (vmCfg name).koch-vm.ports);
  mkVmUnit = name: {
    "koch-vm-${name}" = {
      description = "koch ${name} service VM (rootless qemu)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
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
      };
    };
  };
in
{
  systemd.services = lib.mkMerge (map mkVmUnit vmNames);
  networking.firewall.allowedTCPPorts = lib.unique (lib.flatten (map publishedPorts vmNames));
  users.groups.git = { };
  users.users.alex.extraGroups = [ "immich" "grocy" "git" ];
  # Syncthing identity secrets are staged on the host and shared into that VM.
  systemd.tmpfiles.rules = [
    "d /var/lib/koch-vm/syncthing 0700 alex users -"
    "L+ /var/lib/koch-vm/syncthing/cert.pem - - - - ${config.sops.secrets."syncthing_cert".path}"
    "L+ /var/lib/koch-vm/syncthing/key.pem - - - - ${config.sops.secrets."syncthing_key".path}"
    "d /data/state-store/vm 0755 alex users -"
    "d /data/state-store/git 0755 alex users -"
  ]
    ++ map (name: "d /data/state-store/vm/${name} 0755 alex users -") vmNames;
}
