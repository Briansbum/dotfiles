# mkServiceVM — build a thin single-service NixOS VM using nixpkgs' native
# qemu support (the same machinery behind `nixos-rebuild build-vm`).
#
# Design goals ("rootless container" feel):
#   - one service closure per VM, no home-manager / GUI / sops inside
#   - throwaway root disk; all persistent state lives on the host and is
#     passed through as 9p virtfs shares
#   - run as a systemd *user* unit under alex on the host (rootless qemu)
#
# Port exposure is declarative via `koch-vm.ports`: each entry says which
# guest port to publish, on what protocol, and how it binds on the host.
# The same declaration drives BOTH the qemu hostfwd arguments and the host
# firewall (see vms/runner.nix):
#
#   koch-vm.ports = [
#     { guestPort = 2283; }                          # -> 127.0.0.1:2283
#     { guestPort = 22000; bind = "all-interfaces"; proto = "tcp"; }
#   ];
#
# Usage: call ./mk-service-vm.nix { inherit inputs; name = "chorcy"; modules = [ ... ]; }
{
  inputs,
  # name of the vm, also used for flake output nixosConfigurations.koch-<name>
  name,
  # list of NixOS modules configuring the actual service inside the guest
  modules ? [ ],
}:

inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
  modules = [
    # Pull in nixpkgs' native qemu VM machinery explicitly (it is not part
    # of a default nixosSystem eval).
    "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
    (
      {
        config,
        lib,
        ...
      }:
      let
        cfg = config.koch-vm;
        bindAddr = bind: if bind == "loopback" then "127.0.0.1" else "0.0.0.0";
        fwEntry = p: {
          allowedTCPPorts = lib.optional (p.proto == "tcp") p.guestPort;
          allowedUDPPorts = lib.optional (p.proto == "udp") p.guestPort;
        };
      in
      {
        options.koch-vm = {
          ports = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule (
                { ... }:
                {
                  options = {
                    guestPort = lib.mkOption {
                      type = lib.types.port;
                      description = "Port the service listens on inside the guest.";
                    };
                    hostPort = lib.mkOption {
                      type = lib.types.nullOr lib.types.port;
                      default = null;
                      description = ''
                        Port bound on the host. Defaults to guestPort so Traefik
                        backends keep pointing at localhost:<same-port>.
                      '';
                    };
                    proto = lib.mkOption {
                      type = lib.types.enum [
                        "tcp"
                        "udp"
                      ];
                      default = "tcp";
                    };
                    bind = lib.mkOption {
                      type = lib.types.enum [
                        "loopback"
                        "all-interfaces"
                      ];
                      default = "loopback";
                      description = ''
                        loopback: reachable only from koch itself (Traefik).
                        all-interfaces: published on every host interface and
                        opened in the host firewall (e.g. syncthing peers).
                      '';
                    };
                  };
                }
              )
            );
            default = [ ];
            description = "Guest ports to publish through qemu user-net hostfwd.";
          };

          memory = lib.mkOption {
            type = lib.types.ints.positive;
            default = 512;
            description = "Guest RAM in MiB.";
          };

          vcpus = lib.mkOption {
            type = lib.types.ints.positive;
            default = 2;
          };
        };

        config = {
          networking.hostName = "koch-${name}";

          # No firewall inside the guest — qemu user-net already isolates it.
          networking.firewall.enable = false;

          # Thin guests: no docs, no sudo
          documentation.enable = false;
          security.sudo.enable = false;

          virtualisation = {
            graphics = false;
            memorySize = cfg.memory;
            cores = cfg.vcpus;
            # Throwaway root — everything that matters is a 9p share
            diskSize = 2048;
            # 9p tuning: default msize (~128K or worse) chops big reads into
            # tiny vmexit round-trips. 512K is a sane floor for all guests.
            msize = lib.mkDefault 524288;
            # Guest console on serial so logs land in the unit journal
            qemu.consoles = [ "ttyS0,115200n8" ];
            # Derive native qemu hostfwd args from the declarative port list
            forwardPorts = map (p: {
              from = "host";
              host.address = bindAddr p.bind;
              host.port = if p.hostPort == null then p.guestPort else p.hostPort;
              guest.port = p.guestPort;
              inherit (p) proto;
            }) cfg.ports;
          };

          system.stateVersion = "25.11";
        };
      }
    )
  ] ++ modules;
}
