# Declarative disk layout for sierpinski (HP Chromebook 14-db0003na)
#
# Single 32GB eMMC. btrfs with zstd compression at the default level — density
# is the binding constraint on this disk, and the Nix store compresses well.
#
# /nix is a separate subvolume so any future snapshot scheme can skip it. The
# store is reproducible; there is no reason to snapshot it on a 32GB disk.
#
# mmcblk numbering is not stable across boots when an SD card is present, so
# emmcDevice must be a by-id link; this machine publishes no by-path entry for
# the eMMC. Take the value from `ls -l /dev/disk/by-id` on the target.

{ ... }:
let
  emmcDevice = "/dev/disk/by-id/mmc-DA4032_0xca5e340f";

  btrfsMountOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  disko.devices.disk.emmc = {
    type = "disk";
    device = emmcDevice;
    content = {
      type = "gpt";
      partitions = {
        esp = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };

        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = btrfsMountOptions;
              };
              "@home" = {
                mountpoint = "/home";
                mountOptions = btrfsMountOptions;
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = btrfsMountOptions;
              };
              "@var-log" = {
                mountpoint = "/var/log";
                mountOptions = btrfsMountOptions;
              };
            };
          };
        };
      };
    };
  };
}
