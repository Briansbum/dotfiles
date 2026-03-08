# Declarative disk layout for koch (HP workstation NAS)
#
# Two btrfs RAID1 pools:
#   1. SSD pool (2x SATA SSD) — NixOS root, nix store, boot
#   2. HDD pool (6x 4TB WD Red behind LSI SAS2008 HBA) — data
#
# Provisioned by disko during initial install:
#   nix run github:nix-community/disko -- --mode disko ./nix/koch/disk-config.nix
#
# === DAY-2 OPERATIONS ===
#
# -- Adding a new subvolume --
# 1. Create it on disk:  btrfs subvolume create /data/@new-thing
# 2. Add a new entry to the subvolumes block below
# 3. Run: sudo nixos-rebuild switch --flake .#koch
#
# -- Adding a new disk to the HDD pool --
# 1. Add the disk:       btrfs device add /dev/disk/by-id/NEW-DISK /data
# 2. Rebalance:          btrfs balance start /data
# 3. Add a new disk entry to this file (so reinstalls/docs stay correct)
# 4. Run: sudo nixos-rebuild switch --flake .#koch
#
# -- Replacing a failed disk --
# 1. Mount degraded:     mount -o degraded /dev/sdX /data
# 2. Add replacement:    btrfs device add /dev/disk/by-id/NEW-DISK /data
# 3. Remove failed:      btrfs device remove missing /data
# 4. Rebalance:          btrfs balance start /data
# 5. Update the disk entry in this file
#
# -- Adding an entirely new pool --
# 1. Add a new disk group + subvolumes block below
# 2. For existing systems: format manually, then nixos-rebuild for mounts
# 3. For fresh installs: disko handles it automatically
#
# disko handles initial provisioning and generates fileSystems entries.
# Ongoing pool/subvolume mutations are btrfs commands followed by config updates.

{ ... }: {
  disko.devices = {
    disk = {
      # =====================================================================
      # SSD POOL — btrfs RAID1 for NixOS root
      # 250GB Crucial MX500 + 240GB Intel SSD
      # =====================================================================

      # First SSD: partitioned but btrfs content is empty here — it gets
      # pulled into the RAID1 by ssd1's extraArgs.
      ssd0 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-CT250MX500SSD1_2107E4F9BAD8";
        content = {
          type = "gpt";
          partitions = {
            grub = {
              size = "1M";
              type = "EF02"; # BIOS boot partition for GRUB
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4"; # placeholder — overwritten by btrfs RAID1 from ssd1
                # This partition is referenced by ssd1's btrfs extraArgs
              };
            };
          };
        };
      };

      ssd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-INTEL_SSDSC2BF240A4H_CVDA512303T72403GN";
        content = {
          type = "gpt";
          partitions = {
            grub = {
              size = "1M";
              type = "EF02";
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [
                  "-f"
                  "-d" "raid1"
                  "-m" "raid1"
                  "/dev/disk/by-id/ata-CT250MX500SSD1_2107E4F9BAD8-part2"
                ];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@boot" = {
                    mountpoint = "/boot";
                  };
                };
              };
            };
          };
        };
      };

      # =====================================================================
      # HDD POOL — btrfs RAID1 for data
      # 6x 4TB WD Red (WD40EFRX) behind LSI SAS2008 HBA
      #
      # btrfs RAID1 mirrors each chunk to 2 of the 6 drives.
      # Usable space: ~12TB. Can survive any single drive failure.
      # =====================================================================

      # HDDs 0-4: partitioned, content empty — pulled into RAID1 by hdd5
      hdd0 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4FV5XVK";
        content = {
          type = "gpt";
          partitions.data = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
            };
          };
        };
      };

      hdd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4FV50XT";
        content = {
          type = "gpt";
          partitions.data = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
            };
          };
        };
      };

      hdd2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K6JYSDJF";
        content = {
          type = "gpt";
          partitions.data = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
            };
          };
        };
      };

      hdd3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4TRSAFE";
        content = {
          type = "gpt";
          partitions.data = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
            };
          };
        };
      };

      hdd4 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K7NSZHEU";
        content = {
          type = "gpt";
          partitions.data = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
            };
          };
        };
      };

      # Last HDD: creates the btrfs RAID1 referencing all other HDD partitions
      hdd5 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4EZH27C";
        content = {
          type = "gpt";
          partitions.data = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-f"
                "-d" "raid1"
                "-m" "raid1"
                "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4FV5XVK-part1"
                "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4FV50XT-part1"
                "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K6JYSDJF-part1"
                "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4TRSAFE-part1"
                "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K7NSZHEU-part1"
              ];
              subvolumes = {
                "@data" = {
                  mountpoint = "/data";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "@photos" = {
                  mountpoint = "/data/photos";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "@alex-storage" = {
                  mountpoint = "/data/alex-storage";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "@grocy" = {
                  mountpoint = "/data/grocy";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "@moving-photos" = {
                  mountpoint = "/data/moving-photos";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "@state-store" = {
                  mountpoint = "/data/state-store";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
              };
            };
          };
        };
      };
    };
  };
}
