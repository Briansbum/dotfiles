# nix eval --impure --json --expr '
#   let f = builtins.getFlake (toString ./.);
#   in import ./nix/koch/vms/test-backups.nix { flake = f; }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  systems = flake.nixosConfigurations;
  grocy = systems.koch-grocy.config;
  syncthing = systems.koch-syncthing.config;
  disabled = (systems.koch-grocy.extendModules {
    modules = [ { koch-vm.backup.enable = false; } ];
  }).config;
  host = (systems.koch.extendModules {
    modules = [ {
      koch-vm-backups = {
        enable = true;
        repository = "/tmp/koch-test-repository";
        passwordFile = "/run/koch-test-password";
      };
    } ];
  }).config;
  invalid = (systems.koch.extendModules {
    modules = [ { koch-vm-backups.enable = true; } ];
  }).config;
  jobs = host.services.restic.backups;
  invalidPaths = (systems.koch-grocy.extendModules {
    modules = [ { koch-vm.backup.paths = lib.mkForce [ "/" ]; } ];
  }).config;
  newVm = import ./mk-service-vm.nix {
    inputs = flake.inputs;
    name = "backup-test";
  };
  tests = {
    defaultEnabled = newVm.config.koch-vm.backup.enable;
    defaultMount = newVm.config.virtualisation.sharedDirectories.application-backup.target == "/var/backups/application";
    grocyStaging = grocy.virtualisation.sharedDirectories.application-backup.source == "/data/backups/vms/grocy";
    grocyProducer = builtins.hasAttr "grocy-backup" grocy.systemd.timers;
    grocyGracefulStop = grocy.systemd.services.phpfpm-grocy.serviceConfig.KillSignal == "SIGQUIT"
      && grocy.systemd.services.phpfpm-grocy.serviceConfig.KillMode == "mixed"
      && grocy.systemd.services.phpfpm-grocy.serviceConfig.TimeoutStopSec == "5min";
    grocyBackupTimeout = grocy.systemd.services.grocy-backup.serviceConfig.TimeoutStartSec == "30min";
    directPaths = syncthing.koch-vm.backup.paths == [ "/data/synchspace" ];
    syncthingRequirements = syncthing.koch-vm.backup.requiredMounts == [ "/data" ]
      && syncthing.koch-vm.backup.requiredPaths == [ "/data/synchspace/notes" ];
    grocyMountRequirement = grocy.koch-vm.backup.requiredMounts == [ "/data" ];
    noDirectMount = !(syncthing.virtualisation.sharedDirectories ? application-backup);
    noDirectMarker = syncthing.koch-vm.backup.freshnessFile == null;
    disabledMount = !(disabled.virtualisation.sharedDirectories ? application-backup);
    disabledProducer = !(disabled.systemd.timers ? grocy-backup);
    jobs = builtins.attrNames jobs == [ "koch-vm-grocy" "koch-vm-syncthing" ];
    noPrune = lib.all (job: job.pruneOpts == [ ] && !job.initialize) (builtins.attrValues jobs);
    noTransportByDefault = systems.koch.config.services.restic.backups == { };
    missingSecretsRejected = lib.any (a: !a.assertion) invalid.assertions;
    rootSourceRejected = lib.any (a: !a.assertion) invalidPaths.assertions;
    validHost = lib.all (a: a.assertion) host.assertions;
    validGuest = lib.all (a: a.assertion) grocy.assertions;
    renderedTransport = lib.hasInfix "restic" host.systemd.units."restic-backups-koch-vm-grocy.service".text;
  };
in
assert lib.assertMsg (lib.all (x: x) (builtins.attrValues tests)) "VM backup interface tests failed";
tests
