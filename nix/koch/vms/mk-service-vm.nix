# Shared definition for small, rootless QEMU/KVM service VMs on koch.
{
  inputs,
  name,
  modules ? [ ],
}:

inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
  modules = [
    "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
    ({ config, lib, ... }:
      let
        cfg = config.koch-vm;
        bindAddress = bind: if bind == "loopback" then "127.0.0.1" else "0.0.0.0";
      in {
        options.koch-vm = {
          memory = lib.mkOption { type = lib.types.ints.positive; default = 512; };
          vcpus = lib.mkOption { type = lib.types.ints.positive; default = 2; };
          ports = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule ({ ... }: {
              options = {
                guestPort = lib.mkOption { type = lib.types.port; };
                hostPort = lib.mkOption { type = lib.types.nullOr lib.types.port; default = null; };
                proto = lib.mkOption { type = lib.types.enum [ "tcp" "udp" ]; default = "tcp"; };
                bind = lib.mkOption { type = lib.types.enum [ "loopback" "all-interfaces" ]; default = "loopback"; };
              };
            }));
            default = [ ];
          };
        };

        config = {
          networking.hostName = "koch-${name}";
          networking.firewall.enable = false;
          documentation.enable = false;
          security.sudo.enable = false;
          virtualisation = {
            graphics = false;
            memorySize = cfg.memory;
            cores = cfg.vcpus;
            diskSize = 2048;
            msize = lib.mkDefault 524288;
            qemu.consoles = [ "ttyS0,115200n8" ];
            forwardPorts = map (p: {
              from = "host";
              host.address = bindAddress p.bind;
              host.port = if p.hostPort == null then p.guestPort else p.hostPort;
              guest.port = p.guestPort;
              inherit (p) proto;
            }) cfg.ports;
          };
          system.stateVersion = "25.11";
        };
      })
  ] ++ modules;
}
