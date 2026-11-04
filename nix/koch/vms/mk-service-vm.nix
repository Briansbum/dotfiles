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
          backup = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Register this VM with host backups; disable explicitly for stateless or externally protected VMs.";
            };
            directory = lib.mkOption {
              type = lib.types.str;
              default = "/var/backups/application";
              description = "Guest staging mount. The application owns producing complete, recoverable backups here.";
            };
            hostDirectory = lib.mkOption {
              type = lib.types.str;
              default = "/data/backups/vms/${name}";
              description = "Host source for the guest staging mount.";
            };
            paths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ cfg.backup.hostDirectory ];
              description = "Host paths to back up, replacing the default staging source. No staging mount is created unless hostDirectory is included.";
            };
            exclude = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional restic exclusion patterns.";
            };
            freshnessFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = if builtins.elem cfg.backup.hostDirectory cfg.backup.paths
                then "${cfg.backup.hostDirectory}/.backup-complete" else null;
              description = "Host-side producer completion marker; null disables producer-age checks for direct sources.";
            };
            maxAgeSeconds = lib.mkOption {
              type = lib.types.ints.positive;
              default = 36 * 60 * 60;
              description = "Maximum age of the producer completion marker before refusing an offsite backup.";
            };
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
          assertions = lib.optionals cfg.backup.enable [
            {
              assertion = cfg.backup.paths != [ ] && lib.all (p: lib.hasPrefix "/" p && p != "/") cfg.backup.paths;
              message = "koch-vm.backup.paths must contain non-root absolute host paths.";
            }
            {
              assertion = lib.hasPrefix "/" cfg.backup.directory && cfg.backup.directory != "/";
              message = "koch-vm.backup.directory must be a non-root absolute guest path.";
            }
          ];
          virtualisation.sharedDirectories.application-backup = lib.mkIf
            (cfg.backup.enable && builtins.elem cfg.backup.hostDirectory cfg.backup.paths) {
              source = cfg.backup.hostDirectory;
              target = cfg.backup.directory;
              writable = true;
            };
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
