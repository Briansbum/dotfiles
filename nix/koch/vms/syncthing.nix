# syncthing VM — file sync.
# State:
#   - /data/synchspace (shared folders) via virtiofs
#   - device identity: cert/key are sops secrets decrypted on the HOST and
#     staged by runner.nix into /var/lib/koch-vm/syncthing/, shared into the
#     guest so the device ID stays stable across VM rebuilds.
# Networking: qemu user-net forwards TCP 22000 (sync protocol); local
# discovery (UDP 21027) doesn't traverse user-net NAT and global discovery
# would advertise the slirp address, so every peer lists koch with explicit
# addresses (tcp://koch:22000 and the Tailscale IP).
{
  inputs,
}:
import ./mk-service-vm.nix {
  inherit inputs;
  name = "syncthing";
  modules = [
    (
      { ... }:
      let
        alexHome = "/home/alex";
      in
      {
        users.users.alex.isNormalUser = true;

        services.syncthing = {
          enable = true;
          # These are sources for NixOS' syncthing-copy-keys unit. The
          # destination is managed by the module under configDir.
          cert = "/mnt/syncthing-secrets/cert.pem";
          key = "/mnt/syncthing-secrets/key.pem";
          user = "alex";
          # Match the rootless host virtiofsd's primary GID (users/100).
          # A guest-only GID makes file creation fail with EPERM even when
          # the host tree's mode/ACL otherwise permits the write.
          group = "users";
          dataDir = "/data/synchspace";
          configDir = "${alexHome}/.config/syncthing";
          guiAddress = "0.0.0.0:8384";
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
              # The shared tree is group-writable on the host. Do not copy
              # peer file modes back onto it, or a peer's 0755 directories
              # can make the virtiofs-backed tree unwritable to Syncthing.
              ignorePerms = true;
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

        # Keep group writes enabled; the host tree's setgid directories
        # and default ACLs preserve access for the host syncthing group.
        # Retain the upstream service sandbox, including PrivateMounts and
        # PrivateUsers: the write failure was a primary-GID mismatch.
        systemd.services.syncthing.serviceConfig.UMask = "0002";

        koch-vm = {
          # Direct-source backup: no staging copy/mount or producer marker.
          backup.paths = [ "/data/synchspace" ];
          monitoring.partials = [ ./monitoring/syncthing.alloy ];
          memory = 512;
          ports = [
            # Sync protocol — published on all interfaces so LAN/Tailscale
            # peers can reach the guest; runner.nix opens the host firewall.
            {
              guestPort = 22000;
              bind = "all-interfaces";
            }
            # Web UI: host side binds loopback only, reach via ssh tunnel
            { guestPort = 8384; }
          ];
        };

        virtualisation.sharedDirectories = {
            synchspace = {
              source = "/data/synchspace";
              target = "/data/synchspace";
              writable = true;
            };
            syncthing-secrets = {
              source = "/var/lib/koch-vm/syncthing";
              target = "/mnt/syncthing-secrets";
            };
          };

        # The host owns creation/modes/ACLs of synchspace and .stfolder.
        # Guest tmpfiles must not try to chown them to a guest-only GID.
      }
    )
  ];
}
