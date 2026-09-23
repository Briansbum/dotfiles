# System configuration for sierpinski (Chromebook thin client)
#
# Ghostty workstation: a cage kiosk auto-logs in on tty1 and runs ghostty
# fullscreen. Nothing else graphical — no DE, no greeter, no portals.
# 32GB eMMC is the binding constraint, so store growth is weighed first.

{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    trusted-users = [
      "root"
      "alex"
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  documentation.nixos.enable = false;
  documentation.doc.enable = false;
  documentation.info.enable = false;

  security.sudo.enable = true;
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "sierpinski";
  time.timeZone = "Europe/London";
  environment.variables.EDITOR = "nvim";

  # ---------------------------------------------------------------------------
  # Users
  # ---------------------------------------------------------------------------

  users.users.alex = {
    uid = 1000;
    isNormalUser = true;
    description = "Alex";
    initialHashedPassword = "$y$j9T$Ins5oEP6fb3JGY1tEdQtW.$bnEtJdoGv7t4xDWLfEtL8RllIPAe1TVh/DdqlU72iaA";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh = {
      authorizedKeys.keyFiles = [ ../common/alex-yubikey.pub ];
    };
  };

  # ---------------------------------------------------------------------------
  # Shell — bash redirects to fish (same pattern as koch)
  # ---------------------------------------------------------------------------

  programs.bash.interactiveShellInit = ''
    if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
    then
      shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
      exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
    fi
  '';

  # ---------------------------------------------------------------------------
  # Core services
  # ---------------------------------------------------------------------------

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  services.logind.settings.Login.HandlePowerKey = "suspend";

  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.devmon.enable = true;
  services.tailscale.enable = true;
  services.resolved.enable = true;
  services.pcscd.enable = true;

  networking.networkmanager.enable = true;
  networking.nftables.enable = true;
  networking.firewall.allowedTCPPorts = [
    22 # SSH
  ];

  # ---------------------------------------------------------------------------
  # Ghostty workstation — cage kiosk on tty1
  # ---------------------------------------------------------------------------

  # kmscon existed only because the kernel VT caps out at 512 PSF glyphs and
  # could not render the Nerd Font. Ghostty renders TrueType itself through
  # fontconfig, so the graphical terminal replaces the graphical console and
  # kmscon goes away entirely. Cage is the smallest thing that gives ghostty a
  # Wayland seat: one application, fullscreen, no chrome, no compositor
  # features. The module auto-logs in as the user through its own PAM session.
  # tty2-6 keep plain agetty for recovery, and the kernel VT font there is good
  # enough for fixing a broken kiosk over the local keyboard.
  services.cage = {
    enable = true;
    user = "alex";
    program = "${pkgs.ghostty}/bin/ghostty";
    restartIfChanged = true;
  };

  # If ghostty exits or crashes the kiosk comes back instead of leaving a black
  # VT. A deliberate `systemctl stop cage-tty1` still stays down.
  systemd.services."cage-tty1".serviceConfig = {
    Restart = "always";
    RestartSec = 1;
  };

  fonts.packages = [ pkgs.nerd-fonts.go-mono ];

  # ---------------------------------------------------------------------------
  # System packages
  # ---------------------------------------------------------------------------

  environment.systemPackages = with pkgs; [
    vim
    wget
    htop
    lshw
    pciutils
    usbutils
    btrfs-progs
    alsa-utils
    evtest
  ];

  # ---------------------------------------------------------------------------
  # State version — do NOT change after initial install
  # ---------------------------------------------------------------------------

  system.stateVersion = "26.05";
}
