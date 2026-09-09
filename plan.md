# Plan: Plasma 6 for `cass` on `julia`

## Goal

Install Plasma 6 as an available desktop session on `julia`, keep Niri available for `alex`, and let `cass` configure Plasma interactively through KDE System Settings. Do not add `plasma-manager` or manage Plasma dotfiles with Home Manager.

NixOS will still declaratively install the desktop and its system integration. Only `cass`'s personal Plasma state—panels, shortcuts, themes, displays, widgets, defaults, and similar settings—will remain mutable in `/home/cass`.

## Planned changes

### 1. Enable the system Plasma 6 module

In `nix/julia/configuration.nix`, add:

```nix
services.desktopManager.plasma6.enable = true;
```

Use the full NixOS Plasma module rather than adding individual KDE packages. It supplies the Plasma Wayland session, KWin, KDE portal, KWallet/PAM integration, polkit agent, settings application, and the normal KDE utilities.

Keep the existing settings that enable Niri and LightDM:

- `programs.niri.enable = true;`
- `services.xserver.displayManager.lightdm.enable = true;`

Do not enable SDDM as well. LightDM already supports the required session chooser and was selected specifically so `dm-tool switch-to-greeter` can start another login without terminating the first user's session.

### 2. Let LightDM remember a session per user

Replace:

```nix
services.displayManager.defaultSession = "niri";
```

with:

```nix
services.displayManager.defaultSession = null;
```

This is important for a mixed-desktop machine. When LightDM has a non-null NixOS default, its startup script writes that session into AccountsService for every normal user, overriding per-user session history. With no forced default, LightDM can remember `niri` for `alex` and `plasma` for `cass` independently.

After deployment, each user may need to select their session once from LightDM: `Plasma (Wayland)` for `cass` and `Niri` for `alex`.

### 3. Prevent the Niri shell from starting in Plasma

`programs.dms-shell.systemd.enable = true` currently installs `dms.service` for every user's `graphical-session.target`. Without a guard, Dank Material Shell could start inside `cass`'s Plasma session and compete with Plasma's panel, notification service, and shell.

In `nix/julia/configuration.nix`, add a session condition to that system-wide user unit:

```nix
systemd.user.services.dms.unitConfig.ConditionEnvironment =
  "XDG_CURRENT_DESKTOP=niri";
```

This keeps DMS enabled for a Niri session while causing systemd to skip it in Plasma. Prefer a desktop-session condition over a username condition so the behavior follows the session a user actually selected.

### 4. Stop forcing Niri's identity globally

Remove these machine-wide values from `environment.sessionVariables`:

```nix
XDG_CURRENT_DESKTOP = "niri";
XDG_SESSION_TYPE = "wayland";
```

The Niri and Plasma session launchers set their own correct values. Setting them globally would make Plasma applications and portals incorrectly identify `cass`'s session as Niri.

Keep the generic Wayland application hints unless testing finds an application-specific problem:

```nix
MOZ_ENABLE_WAYLAND = "1";
NIXOS_OZONE_WL = "1";
```

### 5. Make portal selection session-aware

Simplify the hand-written `xdg.portal` block in `nix/julia/configuration.nix` so it no longer forces the GTK portal as the common default or manually adds the GTK implementation. Retain `xdgOpenUsePortal = true`.

The enabled NixOS modules already provide the appropriate implementations and routing:

- Niri adds the GNOME and GTK portals plus `niri-portals.conf`.
- Plasma adds the KDE and GTK portals plus Plasma's portal configuration.

Removing the machine-wide GTK preference allows `XDG_CURRENT_DESKTOP` to select KDE's portal in Plasma while retaining the Niri-specific portal setup.

### 6. Leave Plasma state out of Home Manager

Do not change `flake.nix` to add a `plasma-manager` input or module. Do not add `programs.plasma`, `home.file` entries for KDE files, activation scripts, or generated files such as `kdeglobals`, `kwinrc`, `kglobalshortcutsrc`, or `plasma-org.kde.plasma.desktop-appletsrc`.

Keep `nix/julia/cass.nix` for package installation and non-desktop application configuration such as Fish and Ghostty. Home Manager does not need to be removed merely to make Plasma state mutable.

Remove the existing `xdg.mimeApps` block from `nix/julia/cass.nix`. KDE's Default Applications UI writes `mimeapps.list`; leaving that file under Home Manager would make at least part of the desktop preference state declarative and could prevent or revert changes made in System Settings. After deployment, `cass` can select Brave manually in **System Settings → Apps & Windows → Default Applications**.

## Validation before deployment

1. Format the touched Nix files with the repository's normal formatter.
2. Evaluate the important options:
   - Plasma 6 is enabled.
   - LightDM is enabled and SDDM is not.
   - `services.displayManager.defaultSession` evaluates to `null`.
   - `dms.service` contains `ConditionEnvironment=XDG_CURRENT_DESKTOP=niri`.
3. Build the complete host closure without activating it:

   ```bash
   nix build .#nixosConfigurations.julia.config.system.build.toplevel
   ```

4. Confirm the built display-manager session data contains both Niri and Plasma Wayland sessions.

## Deployment and interactive setup

1. Deploy conservatively first:

   ```bash
   sudo nixos-rebuild test --flake .#julia
   ```

2. Log out `cass`, choose **Plasma (Wayland)** in LightDM's session menu, and log back in.
3. Configure Plasma entirely through System Settings and the normal panel/desktop edit mode.
4. Set Brave as the default browser through KDE now that Home Manager no longer owns `mimeapps.list`.
5. Use `dm-tool switch-to-greeter` and verify `alex` can log into Niri without ending `cass`'s Plasma session.
6. Once both sessions work, make the generation persistent:

   ```bash
   sudo nixos-rebuild switch --flake .#julia
   ```

## Post-deployment checks

For `cass` in Plasma:

- `XDG_CURRENT_DESKTOP` identifies KDE/Plasma rather than Niri.
- `XDG_SESSION_TYPE` is `wayland`.
- `dms.service` is skipped because its condition is false.
- KDE's file picker, screen sharing, notifications, polkit prompts, audio, NetworkManager, Bluetooth, suspend, and screen locking work.
- Plasma settings survive logout, reboot, and a later NixOS rebuild.
- KDE preference files in `/home/cass/.config` are ordinary user-writable files, not links into `/nix/store`.

For `alex` in Niri:

- `XDG_CURRENT_DESKTOP` identifies Niri.
- `dms.service` starts normally.
- Niri's GTK/GNOME portal behavior and existing configuration still work.
- LightDM remembers Niri independently of `cass`'s Plasma selection.

## Rollback

If Plasma or the mixed-session setup causes a regression, select the previous NixOS generation from the boot menu or run `sudo nixos-rebuild switch --rollback`. Plasma's user-created files in `/home/cass` can be left in place; they are inert when Plasma is not running and should not be deleted automatically.
