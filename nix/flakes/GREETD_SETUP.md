# Greetd Setup - Replacing SDDM

## What I've Done

I've replaced SDDM with greetd + gtkgreet running in cage. This gives you a proper Wayland-native display manager that won't fight with your system.

### The Solution

**File: `nix/flakes/greetd.nix`**

This sets up:
- **greetd** as the display manager daemon
- **gtkgreet** as the graphical greeter
- **cage** as a minimal Wayland compositor to run gtkgreet
- Custom CSS styling to match your hyprlock aesthetic:
  - Dark theme with rgba(10, 10, 10, 0.9) backgrounds
  - Go Mono font throughout
  - Your omnium.png as the background
  - Input fields styled to match hyprlock's dimensions (320x55)

### How to Apply

```bash
sudo nixos-rebuild switch
```

### What Changed in configuration.nix

1. Removed the `sddmHyprTheme` derivation
2. Removed the SDDM service configuration
3. Added import for `./greetd.nix`
4. Removed sddmHyprTheme from systemPackages

### Why This Works Better Than SDDM

- Cage is a proper Wayland compositor designed for single-app kiosk mode
- GTKGreet is designed to work with greetd's authentication flow
- No more X11 compatibility layers or Wayland hacks
- The CSS gives you full control over the appearance

### Troubleshooting

If you need to debug:
```bash
journalctl -u greetd -f
```

If you need to get back in via TTY: `Ctrl+Alt+F2`
