# Provisioning koch from scratch

Koch is an HP Z420 workstation running NixOS as a headless NAS.

## Hardware

- **CPU:** Intel Xeon E5-2667 v2 (8C/16T @ 3.3GHz)
- **RAM:** 64GB ECC
- **Boot:** BIOS (not UEFI) — GRUB installed to both SSDs
- **NIC:** Intel e1000e — needs EEE and interrupt throttle disabled
- **HBA:** Broadcom/LSI SAS2008 (Dell 6Gbps) — mpt3sas driver
- **SSDs:** 250GB Crucial MX500 + 240GB Intel (btrfs RAID1, NixOS root)
- **HDDs:** 6x 4TB WD Red WD40EFRX (btrfs RAID1, data)

## Prerequisites

1. A machine with nix installed (any Linux or macOS host works)
2. Root SSH access to the target box (any running Linux — Proxmox is fine)
3. All data backed up to B2 (see [Pre-migration backups](#pre-migration-backups) below)

## Pre-migration backups

If migrating from TrueNAS, complete these steps first. If provisioning fresh, skip to [Install](#install).

### Immich database dump

```bash
ssh root@<truenas-ip>
docker exec ix-immich-pgvecto-1 pg_dump -U postgres immich \
  | gzip > "/mnt/Main Pool/alex-storage/immich-dump.sql.gz"
```

### Push data to B2

```bash
# Existing photos backup should already be current — verify:
rclone check "/mnt/Main Pool/Photos" b2:truenas-photos-pool --one-way

# Create bucket for non-photo data and push:
rclone mkdir b2:nas-migration-spring-2026
rclone copy "/mnt/Main Pool/alex-storage" b2:nas-migration-spring-2026/alex-storage -P
rclone copy "/mnt/.ix-apps/app_mounts/grocy/config" b2:nas-migration-spring-2026/grocy -P
```

### Release the HBA

If the LSI SAS2008 is passed through to a TrueNAS VM, shut the VM down
so the HBA (and the 6 HDDs behind it) are visible to the host OS.

## Install

nixos-anywhere SSHes into the running system, kexec's into a NixOS
installer in RAM, runs disko to partition/format all disks, and installs
NixOS — all remotely. No USB stick or physical access needed.

**This destroys everything on the target machine.** Proxmox, TrueNAS,
all VMs, all local data — gone. Verify backups before proceeding.

Run the following from any machine with nix and SSH access to the target:

```bash
cd ~/dotfiles
nix run github:nix-community/nixos-anywhere -- \
  --flake .#koch \
  root@<target-ip>
```

This uses:
- `disk-config.nix` — disko partitions and formats all 8 disks (btrfs RAID1)
- `configuration.nix` — services, firewall, backups
- `hardware.nix` — kernel modules, boot loader, NIC tuning

The install takes ~10-20 minutes depending on download speed.

## Post-install

### First login

nixos-anywhere sets no root password and root SSH login is disabled in
the config. Console access is required (or leave a monitor plugged in) for
this one step:

```bash
# At the console, log in as root (no password set yet), then:
passwd alex
```

Alternatively, temporarily add a `hashedPassword` to `users.users.alex`
in `configuration.nix` before running nixos-anywhere, then remove it
after first login.

### Join Tailscale

```bash
ssh alex@<ip>
sudo tailscale up
```

### Clone dotfiles properly

The install used a local copy. Replace it with a proper git checkout:

```bash
git clone git@github.com:Briansbum/dotfiles.git ~/dotfiles
sudo nixos-rebuild switch --flake ~/dotfiles#koch
```

### Wire up sops-nix secrets

B2 credentials for rclone backups are managed via sops-nix. Generate an
age key on koch, add its public key to `.sops.yaml`, and encrypt the
secrets:

```bash
# On koch:
sudo mkdir -p /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/keys.txt
# Note the public key printed

# On the admin machine, add the public key to .sops.yaml and re-encrypt:
sops updatekeys nix/koch/secrets.yaml
sudo nixos-rebuild switch --flake ~/dotfiles#koch
```

## Data restore

Run these in tmux — the photos restore is ~517GB.

```bash
# Photos (the big one)
rclone copy b2:truenas-photos-pool /data/photos -P --transfers 8

# Other data
rclone copy b2:nas-migration-spring-2026/alex-storage /data/alex-storage -P
rclone copy b2:nas-migration-spring-2026/grocy /data/grocy -P

# Immich database
gunzip /data/alex-storage/immich-dump.sql.gz
sudo -u immich psql immich < /data/alex-storage/immich-dump.sql
sudo systemctl restart immich-server
```

## Verify

```bash
# Backup timers are scheduled
systemctl list-timers

# btrfs pools healthy
btrfs fi usage /
btrfs fi usage /data

# SMART looks good
sudo smartctl -a /dev/sda

# Services responding
curl -s http://localhost:2283  # Immich
curl -s http://localhost:80    # Grocy

# NFS exports visible
showmount -e localhost
```

## Post-migration tasks

- Configure Immich external libraries in the Immich UI
- Update mandelbrot NFS mount paths (`nix/mandelbrot/hardware.nix`)
- Verify B2 backup timers fire and succeed after sops-nix is wired up

## Re-provisioning

To wipe and reinstall koch in future, the process is the same: boot any
Linux live USB (or leave the existing NixOS running), ensure root SSH
access, and run nixos-anywhere again. disko handles the full disk layout
declaratively.
