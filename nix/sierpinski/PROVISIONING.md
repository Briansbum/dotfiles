# Provisioning sierpinski from scratch

Sierpinski is an HP Chromebook 14-db0003na (ChromeOS board `careena`, baseboard
`grunt`) converted to UEFI with MrChromebox Full ROM firmware and running NixOS
as a console-only thin client.

## Hardware

- **CPU:** AMD A4-9120C (Stoney Ridge, 2C/2T, Excavator)
- **GPU:** Radeon R4, GCN 3 class, `amdgpu`
- **RAM:** 4GB DDR4, soldered, not upgradable
- **Storage:** 32GB eMMC, soldered, not upgradable
- **Display:** 14 inch, 1366x768
- **Wi-Fi:** Qualcomm Atheros QCA6174 802.11ac, `ath10k_pci`
- **Boot:** UEFI with `systemd-boot`, after the firmware conversion
- **Security chip:** Cr50 GSC, partial TPM 2.0 only

Two constraints drive every decision here. Nothing is ever built on this
machine, because 4GB of RAM and slow eMMC make local compilation unacceptable.
The 32GB disk is the binding resource, not the CPU, so store growth is weighed
before anything else.

## Prerequisites

1. The MrChromebox firmware conversion is complete and the machine boots to a
   UEFI firmware screen. See `flash-work` in the repository root for that
   procedure, including the battery disconnect that disables hardware write
   protect.
2. A NixOS minimal ISO on USB, booted on the target, with an IP address and
   root SSH reachable from the fleet.
3. An x86_64-linux fleet host to drive the install from: `koch`, `mandelbrot`,
   or `julia`. The install and every subsequent deploy build the closure on the
   invoking machine, so the origin must already be x86_64-linux. The MacBook is
   aarch64-darwin and is not a deploy origin.

## Hardware survey

The survey has been run from the live ISO and its results are carried in
`hardware.nix` and `disk-config.nix`. Repeat it from the ISO on a rebuild:

```bash
lspci -nnk                 # wifi, gpu, audio controller and bound drivers
lsblk -o NAME,PATH,SIZE,MODEL
ls -l /dev/disk/by-id /dev/disk/by-path
sudo -i dmesg | grep -i acp
uname -r
efibootmgr -v              # confirm UEFI variables are writable
free -h
sudo nix-shell -p evtest --run evtest   # keyboard: pick "AT Translated Set 2 keyboard"
sudo rtcwake -m mem -s 30               # suspend and resume unattended
```

`aplay` and `evtest` are absent from the minimal ISO, so `evtest` is run through
`nix-shell -p evtest`, while `rtcwake` is present as-is. Reading the kernel ring
buffer needs `sudo -i dmesg` rather than `sudo dmesg`.

What the survey settled:

- Wi-Fi is a Qualcomm Atheros QCA6174 802.11ac at PCI 01:00.0, `[168c:003e]`
  rev 32, subsystem Rivet Networks `[1a56:1435]`. `ath10k_pci` binds, loads
  firmware `WLAN.RM.4.4.1-00309- api 6` with board file api 2, and `wlp1s0`
  associates and takes both IPv4 and IPv6 addresses. Those blobs come from
  `hardware.enableRedistributableFirmware` in `hardware.nix`, which is
  load-bearing rather than precautionary.
- The installer kernel loaded `sdhci_pci`, `sdhci`, `sdhci_uhs2`, `mmc_block`,
  `xhci_pci` and `usb_storage`. `boot.initrd.availableKernelModules` in
  `hardware.nix` lists `sdhci_pci`, `mmc_block`, `xhci_pci`, `usb_storage`,
  `usbhid` and `sd_mod`, and `sdhci` and `sdhci_uhs2` arrive as dependencies of
  `sdhci_pci`. No change is needed.
- The platform reports as `Google Careena/Careena, BIOS MrChromebox-2606.1
  07/14/2026`, on kernel 7.2.0 from the ISO. `efibootmgr` reads and writes, and
  the firmware auto-creates `Boot0001 Internal eMMC`. `amdgpu` binds the AMD
  Stoney GPU `[1002:98e4]` with Display Core 3.2.384 on DCE 11.0, and UVD and
  VCE initialise. RAM reads as 3.7 GiB usable, with no swap on the ISO.
- The keyboard needs no remapping. `evtest` on the AT Translated Set 2 keyboard
  reports:

  ```
  Search key            code 125  KEY_LEFTMETA
  Left Ctrl             code 29   KEY_LEFTCTRL
  Left Alt              code 56   KEY_LEFTALT
  Backspace             code 14   KEY_BACKSPACE
  Esc                   code 1    KEY_ESC
  Top row, left to right  codes 59 through 68, KEY_F1 through KEY_F10
  ```

  The Search key emitting `KEY_LEFTMETA` is the wanted behaviour: it is Super and
  it stays Super. The top row emits plain function keys rather than the ChromeOS
  browser keys because the `vivaldi_fmap` driver supplies the Chromebook function
  row map. There is no physical Caps Lock key and no physical Delete key.
  `KEY_CAPSLOCK` (58) and `KEY_DELETE` (111) both appear in the device's declared
  capability list, because the AT keyboard driver advertises a generic capability
  set regardless of the chassis, but neither is ever emitted, and the event stream
  is the evidence. The power button does not reach `evtest` at all, since logind
  consumes the press and acts on it first. `configuration.nix` sets
  `services.logind.settings.Login.HandlePowerKey = "suspend"`, so the button
  suspends the machine rather than powering it off.
- Suspend works. `sudo rtcwake -m mem -s 30` suspended and resumed cleanly,
  unattended:

  ```
  [  384.424300] PM: suspend entry (deep)
  [  386.067159] PM: suspend exit
  ```

  The kernel takes the deep S3 path rather than s2idle, so no
  `mem_sleep_default=deep` kernel parameter is needed. In `/sys/power/mem_sleep`
  the bracketed entry marks the selected mode rather than the first listed one,
  which is easy to misread. The 1.6 seconds between the two lines is not the
  sleep duration: dmesg timestamps are monotonic, the monotonic clock is frozen
  across deep S3, and the figure is the cost of the suspend and resume code paths.
  Wi-Fi survives the cycle. `ath10k` does not re-probe after resume, and its only
  line during the cycle is a routine "DFS region 0x0 not supported" capability
  complaint at suspend entry. On resume the kernel logs "[Firmware Bug]: CPU 1:
  APIC ID mismatch. CPUID: <id> APIC: <id>", which is a coreboot quirk on AMD; the
  kernel uses the APIC value and continues, and it has no runtime effect. Early in
  boot the kernel also reports "BIOS may not properly restore RDRAND after
  suspend, hiding RDRAND via CPUID", so this platform presents no RDRAND to
  userspace at all. `rdrand=force` overrides that, at the cost of trusting the
  firmware to restore it. The capture was filtered to the PM suspend and resume
  lines and `ath10k`, so it does not by itself prove that `amdgpu` resumed
  cleanly, though the display did come back.

## The eMMC device path

`nix/sierpinski/disk-config.nix` binds the target device once, at the top of the
file:

```nix
emmcDevice = "/dev/disk/by-id/mmc-DA4032_0xca5e340f";
```

That is the recorded value for this machine. It publishes no `by-path` entry for
the eMMC at all, so the `by-id` link is the one to use. Never use a raw
`/dev/mmcblkN` node: mmcblk numbering is not stable across boots when an SD card
is present. The eMMC enumerates as `mmcblk1` behind the O2 Micro OZ620 card reader
controller at PCI 02:00.0, `[1217:8620]`, negotiates HS200, and brings
`mmcblk1boot0`, `mmcblk1boot1` and `mmcblk1rpmb` with it. The empty microSD slot
is a second, separate controller, the AMD FCH SD Flash Controller at PCI
00:14.7, `[1022:7906]`, which enumerates as `mmc0` and holds no card.

This value is used at partition time only. Disko generates the resulting
`fileSystems` entries against `/dev/disk/by-partlabel/disk-emmc-*`, so the
running system does not depend on the enumeration order either.

Confirm the layout resolves against the real device before it destroys
anything:

```bash
nix run github:nix-community/disko -- --mode disko --dry-run ./nix/sierpinski/disk-config.nix
```

## Set alex's password before installing

`nixos-anywhere` sets no root password and leaves root locked, so alex is the
only account that can reach the console. `users.users.alex` in
`nix/sierpinski/configuration.nix` must carry a password hash before the install
runs. Without one no account can log in, and this machine has no ethernet port
to fall back on.

Generate the hash on a fleet host:

```bash
nix run nixpkgs#mkpasswd -- -m yescrypt
```

Then set it on `users.users.alex`:

```nix
initialHashedPassword = "$y$j9T$...";
```

`initialHashedPassword` applies when the account is created, and
`users.mutableUsers` defaults to true, so `passwd` overrides it afterwards and
the committed hash stops being the live value.

Deploys depend on this as well. `security.sudo` prompts for alex's password, so
`deploy-sierpinski`, which runs `nixos-rebuild --sudo`, has nothing to
authenticate against until a password exists.

## Install

From `koch`, `mandelbrot`, or `julia`, with the repository checked out:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#sierpinski \
  root@<target-ip>
```

`nixos-anywhere` is also available as `nixos-anywhere` inside the `nixadmin`
dev shell on x86_64-linux.

**This destroys everything on the 32GB eMMC.** The disk still holds the original
ChromeOS partition layout, which disko destroys, and nothing on the device is
being kept.

This uses:

- `disk-config.nix` for the GPT layout, a 512MB ESP, and a btrfs root with
  `compress=zstd` and `noatime` on the `@`, `@home`, `@nix`, and `@var-log`
  subvolumes
- `hardware.nix` for `systemd-boot`, the eMMC and AMD kernel modules, zram swap,
  and periodic fstrim
- `configuration.nix` for SSH, Tailscale, NetworkManager, and the space hygiene
  settings

## Post-install

### First login

Log in at the console as alex, using the password whose hash went into
`configuration.nix` before the install. Change it once:

```bash
passwd alex
```

Root has no password and stays locked, and root SSH login is disabled in the
configuration.

### Join Tailscale

```bash
ssh alex@<ip>
sudo tailscale up
```

## Deploying afterwards

From the `nixadmin` dev shell on an x86_64-linux fleet host:

```bash
nix develop .#nixadmin
deploy-sierpinski
```

That wraps:

```bash
nixos-rebuild switch --flake .#sierpinski \
  --target-host alex@sierpinski --sudo --no-reexec
```

Override the destination with `TARGET_HOST=alex@<ip> deploy-sierpinski` when
Tailscale name resolution is not available yet.

SSH to `alex@sierpinski` authenticates against `nix/common/alex-yubikey.pub`. If
the deploy is driven from a shell on koch over SSH, that session needs agent
forwarding for the YubiKey to be reachable, otherwise the push fails on
authentication after the build has already succeeded. This is the most common
first-attempt failure.

## Verify

```bash
# Nothing compiled on the target: substitutions and copies only
journalctl -u nix-daemon --since "10 min ago"

# Space hygiene is actually armed
systemctl status fstrim.timer nix-gc.timer
zramctl

# Compression is in effect and the generation limit is holding
btrfs filesystem usage /
bootctl list

# Networking
tailscale status
lspci -nnk | grep -iA3 network
```

## Adding secrets later

The host holds no secrets, so there is no `secrets.yaml` and no `sops-nix`
module in its flake entry. To add them, follow the same procedure koch uses:
generate an age key on the host at `/var/lib/sops-nix/keys.txt`, add the public
key to `.sops.yaml` with a creation rule for
`nix/sierpinski/secrets\.yaml$`, add `sops-nix.nixosModules.sops` to the host's
module list in `flake.nix`, then deploy. The `nixadmin` shell picks up a
`sops-sierpinski` script automatically once the file exists.

## Not yet done

These were deliberately left out of the initial bring-up and are still open on
the running hardware.

- **Audio.** The codec path is AMD ACP with a Dialog DA7219 codec and a
  MAX98357A amplifier. The modules load, `snd_soc_acp_da7219mx98357_mach`,
  `snd_soc_da7219`, `snd_soc_max98357a`, `snd_soc_adau7002`, `acp_audio_dma`
  and `designware_i2s` among them, and the codec itself attaches over i2c as
  `i2c-DLGS7219:00`, but the machine driver fails to probe and no card comes
  up:

  ```
  cz-da7219-max98357a AMD7219:00: ASoC: CPU DAI designware-i2s.1 not registered
  cz-da7219-max98357a AMD7219:00: ASoC: DAPM unknown pin Headphone Jack
  cz-da7219-max98357a AMD7219:00: Could not create device link to i2c-DLGS7219:00
  ```

  The I2S CPU DAIs never register, so the ASoC card never binds. `amdgpu` warns
  on the same bring-up path during PCI probe, "PM domains can only be changed
  for unbound devices" at `drivers/base/power/common.c:431` in
  `dev_pm_domain_set`, reached through `acp_genpd_add_device` and
  `acp_hw_init`. This is a kernel-side problem and is where the work starts.
  Packaging the `alsa-ucm-conf` profiles is a later step: they are not upstream,
  and the chrultrabook audio scripts install them on FHS distributions and will
  not work here, so they need packaging as a derivation, but no UCM profile can
  help while there is no card.
- **Delete key.** No key on this chassis produces `KEY_DELETE`. If one is wanted
  it has to be synthesised, for example as a chord through `keyd`. This is a
  preference decision rather than a hardware unknown.
- **Desktop environment.** The machine is console-only for now. Any graphical
  stack needs weighing against a 4GB RAM budget and the 32GB disk.
