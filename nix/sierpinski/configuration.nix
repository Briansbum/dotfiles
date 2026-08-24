# System configuration for sierpinski (Chromebook thin client)
#
# Console only — SSH and Tailscale, no graphical stack.
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

  networking.networkmanager.enable = true;
  networking.nftables.enable = true;
  networking.firewall.allowedTCPPorts = [
    22 # SSH
  ];

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
