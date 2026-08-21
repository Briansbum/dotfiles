# runner.nix — host-side (koch) glue that runs each service VM as a
# rootless qemu process under the `alex` user via systemd system units
# (User=alex, so no VM ever runs as root).
#
# Each unit execs the run script produced by nixpkgs' native qemu support
# (config.system.build.vm of the corresponding flake output
# nixosConfigurations.koch-<name>).
#
# Everything that varies per VM is read from its own config: ports declared
# in the guest module (koch-vm.ports) drive BOTH the qemu hostfwd args and,
# here, the host firewall — a port bound to "all-interfaces" is opened on
# koch; loopback ports stay closed to the outside.
{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

let
  vmNames = [
    "chorcy"
    "grocy"
    "immich"
    "syncthing"
  ];

  vmCfg = name: inputs.self.nixosConfigurations."koch-${name}".config;

  # Ports exposed beyond loopback must be opened in koch's firewall so LAN /
  # Tailscale peers can reach them through qemu's hostfwd.
  publishedPorts =
    name:
    let
      cfg = vmCfg name;
    in
    map (p: p.guestPort) (
      lib.filter (p: p.bind == "all-interfaces" && p.proto == "tcp") cfg.koch-vm.ports
    );

  mkVmUnit = name: {
    "koch-vm-${name}" = {
      description = "koch ${name} service VM (rootless qemu)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        # Persistent guest disk lives outside the nix store, under /data
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

  users.users.alex.extraGroups = [
    "immich" # access to /data/photos/immich for the immich VM's 9p share
    "grocy"
  ];

  # syncthing cert/key sops secrets are declared in ../configuration.nix;
  # here we just expose them to the VM via a stable path.
  systemd.tmpfiles.rules = [
    "d /var/lib/koch-vm/syncthing 0700 alex users -"
    "L+ /var/lib/koch-vm/syncthing/cert.pem - - - - ${config.sops.secrets."syncthing_cert".path}"
    "L+ /var/lib/koch-vm/syncthing/key.pem - - - - ${config.sops.secrets."syncthing_key".path}"
    "d /data/state-store/vm 0755 alex users -"
  ]
  ++ map (name: "d /data/state-store/vm/${name} 0755 alex users -") vmNames;
}
