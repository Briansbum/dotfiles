# Custom NixOS installer ISO for koch
#
# Build with:
#   nix build .#nixosConfigurations.koch-installer.config.system.build.isoImage
#
# Write to USB with:
#   sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
#
# Boot the USB, log in as root (no password), then run:
#   koch-install

{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  # Bake the dotfiles into the ISO at /etc/dotfiles
  environment.etc."dotfiles".source = ../..;

  # Pre-install tools + the bootstrap script
  environment.systemPackages = with pkgs; [
    git
    vim
    rclone
    btrfs-progs
    smartmontools
    ethtool
    lshw
    tmux
    jq
    (writeShellScriptBin "koch-install" ''
      set -euo pipefail

      DOTFILES="/etc/dotfiles"
      DISK_CONFIG="$DOTFILES/nix/koch/disk-config.nix"

      echo "============================================"
      echo "  koch NixOS installer"
      echo "============================================"
      echo ""
      echo "This will WIPE all disks and install NixOS."
      echo ""
      echo "SSDs (root):"
      echo "  - ata-CT250MX500SSD1_2107E4F9BAD8"
      echo "  - ata-INTEL_SSDSC2BF240A4H_CVDA512303T72403GN"
      echo ""
      echo "HDDs (data):"
      echo "  - 6x WD Red 4TB (WD40EFRX)"
      echo ""

      # Check all expected disks are present
      echo "Checking disks..."
      MISSING=0
      for id in \
        ata-CT250MX500SSD1_2107E4F9BAD8 \
        ata-INTEL_SSDSC2BF240A4H_CVDA512303T72403GN \
        ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4FV5XVK \
        ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4FV50XT \
        ata-WDC_WD40EFRX-68N32N0_WD-WCC7K6JYSDJF \
        ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4TRSAFE \
        ata-WDC_WD40EFRX-68N32N0_WD-WCC7K7NSZHEU \
        ata-WDC_WD40EFRX-68N32N0_WD-WCC7K4EZH27C; do
        if [ -e "/dev/disk/by-id/$id" ]; then
          echo "  OK: $id"
        else
          echo "  MISSING: $id"
          MISSING=1
        fi
      done

      if [ "$MISSING" -eq 1 ]; then
        echo ""
        echo "Some disks are missing. Available disks:"
        ls /dev/disk/by-id/ | grep -v part
        echo ""
        echo "If the disk IDs have changed (e.g. different naming under mpt3sas),"
        echo "edit $DISK_CONFIG and re-run this script."
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          exit 1
        fi
      fi

      echo ""
      read -p "THIS WILL DESTROY ALL DATA ON THE ABOVE DISKS. Type 'yes' to continue: " CONFIRM
      if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 1
      fi

      echo ""
      echo "=== Step 1/4: Partitioning and formatting with disko ==="
      ${pkgs.disko}/bin/disko --mode destroy,format,mount "$DISK_CONFIG"

      echo ""
      echo "=== Step 2/4: Copying dotfiles to target ==="
      mkdir -p /mnt/etc
      cp -r "$DOTFILES" /mnt/etc/dotfiles

      echo ""
      echo "=== Step 3/4: Installing NixOS ==="
      nixos-install --flake "/mnt/etc/dotfiles#koch" --no-root-passwd

      echo ""
      echo "=== Step 4/4: Post-install ==="
      echo ""
      echo "Installation complete! Next steps:"
      echo ""
      echo "  1. Reboot:  reboot"
      echo "  2. Log in as root, set alex's password:  passwd alex"
      echo "  3. Log in as alex"
      echo "  4. Join tailscale:  sudo tailscale up"
      echo "  5. Clone dotfiles properly:"
      echo "       git clone git@github.com:Briansbum/dotfiles.git ~/dotfiles"
      echo "  6. Rebuild from git:"
      echo "       sudo nixos-rebuild switch --flake ~/dotfiles#koch"
      echo "  7. Restore data from B2 (run in tmux):"
      echo "       rclone copy b2:truenas-photos-pool /data/photos -P --transfers 8"
      echo "       rclone copy b2:koch-data-backup/alex-storage /data/alex-storage -P"
      echo "       rclone copy b2:koch-data-backup/grocy /data/grocy -P"
      echo "  8. Restore Immich DB:"
      echo "       gunzip /data/alex-storage/immich-dump.sql.gz"
      echo "       sudo -u postgres psql immich < /data/alex-storage/immich-dump.sql"
      echo "       sudo systemctl restart immich-server"
      echo "  9. Wire up sops-nix secrets for B2 credentials"
      echo " 10. Verify: systemctl list-timers"
      echo ""
    '')
  ];

  # mpt3sas for the LSI SAS2008 HBA — needed so the installer can see the HDDs
  boot.initrd.availableKernelModules = [ "ahci" "mpt3sas" "sd_mod" "usb_storage" "xhci_pci" ];

  # e1000e tuning so networking works properly during install
  boot.extraModprobeConfig = "options e1000e EEE=0 InterruptThrottleRate=0";

  # Enable SSH so you can install from another machine if the cupboard is awkward
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIfEsNDo0qIws3jPsuD9YNlqS+a4/T9Zl5p8TmjGv7UVnYaiDBNU/MSedshMGo9OsRW9Eu7NFVz7b+w3dmj+XNY= alex@AlexF.local"
  ];

  image.baseName = lib.mkForce "koch-installer";
}
