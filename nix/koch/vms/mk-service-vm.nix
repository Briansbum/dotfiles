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
          diskSize = lib.mkOption { type = lib.types.ints.positive; default = 2048; };
          monitoring.partials = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            default = [ ];
            description = ''
              Alloy configuration fragments installed by the host. A service
              VM uses these fragments to register its Prometheus or OTLP
              health endpoints without coupling the VM to the host's Alloy
              configuration.
            '';
          };
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
          # QEMU is run with -nographic and its serial console is inherited by
          # the host runner. Forward the guest journal to that console so the
          # host systemd unit (and therefore Alloy's journal source) receives
          # guest logs in real time.
          services.journald.settings.Journal = {
            ForwardToConsole = true;
            MaxLevelConsole = "info";
          };
          security.sudo.enable = false;
          virtualisation = {
            graphics = false;
            memorySize = cfg.memory;
            cores = cfg.vcpus;
            diskSize = cfg.diskSize;
            qemu.forceAccel = true;
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
