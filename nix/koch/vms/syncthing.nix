# syncthing VM — file sync.
# State:
#   - /data/synchspace (shared folders) via 9p
#   - device identity: cert/key are sops secrets decrypted on the HOST and
#     staged by runner.nix into /var/lib/koch-vm/syncthing/, shared into the
#     guest so the device ID stays stable across VM rebuilds.
# Networking: qemu user-net forwards TCP 22000 (sync protocol); local
# discovery (UDP 21027) doesn't traverse user-net NAT — peers must be
# configured with explicit addresses (they already are: static device IDs +
# introductions). Relaying via Tailscale/LAN TCP still works.
{
  inputs,
}:
import ./mk-service-vm.nix {
  inherit inputs;
  name = "syncthing";
  modules = [
    (
      {
        config,
        lib,
        ...
      }:
      let
        alexHome = "/home/alex";
      in
      {
        users.users.alex.isNormalUser = true;
        users.groups.syncthing = { };

        services.syncthing = {
          enable = true;
          cert = "${alexHome}/.config/syncthing/cert.pem";
          key = "${alexHome}/.config/syncthing/key.pem";
          user = "alex";
          group = "syncthing";
          dataDir = "/data/synchspace";
          configDir = "${alexHome}/.config/syncthing";
          overrideDevices = true;
          overrideFolders = true;
          settings = {
            openDefaultPorts = false; # firewall disabled in guest; hostfwd covers it
            localAnnounceEnabled = false; # user-net NAT blocks broadcast anyway
            devices = {
              doccla-mac.id = "LI4CXJ6-WCQVB7Y-LZNZJYR-XKT3RYB-W7IDWIJ-JQKGHI4-OLJMCKY-ZLX57QU";
              mandelbrot.id = "LIXMZLQ-F5CQCIQ-JN6OLEZ-QUDKAQC-ZAHAPRY-Y76AREC-A7OGEUT-VSGPKQL";
              julia.id = "PCDES7Z-7DYANWV-RGMXFMP-EVAV4MF-5DB4I3M-HEEPXAA-DTRUML4-MFPSBAP";
              pixel10.id = "KIRCSTT-YWT37YF-BNIFKK2-LRE2Q4V-LRNYPL6-5WVYV6U-PB2XBYN-5CNQCA4";
              # All peers reach us via koch's LAN IP on tcp://koch:22000 —
              # the host forwards that port to this guest (see runner.nix).
            };
            folders."synchspace" = {
              path = "/data/synchspace";
              devices = [
                "doccla-mac"
                "mandelbrot"
                "julia"
                "pixel10"
              ];
              versioning = {
                type = "simple";
                params.keep = "10";
              };
            };
          };
        };

        # Stage cert/key from the host share (see runner.nix tmpfiles)
        # Stage cert/key from the host share before first start
        systemd.services.syncthing.preStart = lib.mkAfter ''
          install -m 600 /mnt/syncthing-secrets/cert.pem ${alexHome}/.config/syncthing/cert.pem
          install -m 600 /mnt/syncthing-secrets/key.pem  ${alexHome}/.config/syncthing/key.pem
        '';

        koch-vm = {
          memory = 512;
          ports = [
            # Sync protocol — published on all interfaces so LAN/Tailscale
            # peers can reach the guest; runner.nix opens the host firewall.
            {
              guestPort = 22000;
              bind = "all-interfaces";
            }
            # Web UI — loopback only, reach via ssh tunnel
            { guestPort = 8384; }
          ];
        };

        virtualisation.sharedDirectories = {
            synchspace = {
              source = "/data/synchspace";
              target = "/data/synchspace";
              securityModel = "none";
            };
            syncthing-secrets = {
              source = "/var/lib/koch-vm/syncthing";
              target = "/mnt/syncthing-secrets";
            };
          };

        systemd.tmpfiles.rules = [
          "d /data/synchspace 2775 alex syncthing -"
          "d /data/synchspace/.stfolder 2775 alex syncthing -"
        ];
      }
    )
  ];
}
