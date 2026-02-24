{ config, pkgs, inputs, lib, ... }:

{
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  security.sudo.enable = true;

  users.users.alex = {
    isNormalUser = true;
    description = "Alex";
    extraGroups = ["wheel" "plugdev" "networkmanager" "video"];
  };

  users.users.cass = {
    isNormalUser = true;
    description = "Cass";
    extraGroups = ["wheel" "networkmanager" "video"];
  };

  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.devmon.enable = true;
  services.tailscale.enable = true;
  services.avahi.enable = true;
  services.playerctld.enable = true;
  services.resolved.enable = true;

  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

  # Fingerprint reader (Framework 13 Goodix MOC sensor)
  services.fprintd.enable = true;

  # Firmware updates (needed for fingerprint sensor firmware)
  services.fwupd.enable = true;

  # Fingerprint auth at login screen and for sudo
  security.pam.services.greetd.fprintAuth = true;
  security.pam.services.sudo.fprintAuth = true;

  fonts.packages = [
    pkgs.nerd-fonts.go-mono
  ];

  programs.bash = {
    interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    enableBrowserSocket = true;
    pinentryPackage = pkgs.pinentry-gtk2;
  };

  nixpkgs.config.allowUnfree = true;

  # Intel integrated graphics
  hardware.graphics = {
    enable = true;
  };

  networking.hostName = "julia";
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/London";

  services.xserver.enable = true;

  programs.niri.enable = true;
  programs.dms-shell = {
    enable = true;

    systemd = {
      enable = true;
      restartIfChanged = true;
    };

    enableSystemMonitoring = true;
    enableDynamicTheming = true;
    enableAudioWavelength = true;
  };

  services.displayManager.dms-greeter = {
    enable = true;
    
    compositor = {
      name = "niri";
    };
  
    configHome = "/home/alex";
  
    logs = {
      save = true;
      path = "/tmp/dms-greeter.log";
    };
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    config = {
      common.default = ["gtk"];
    };
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-gnome
    ];
  };

  environment.sessionVariables = {
      XDG_CURRENT_DESKTOP = "niri";
      XDG_SESSION_TYPE = "wayland";
      MOZ_ENABLE_WAYLAND = "1";
      NIXOS_OZONE_WL = "1";
  };
  environment.variables.EDITOR = "nvim";

  # Enable sound.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
  };

  services.gnome.gnome-keyring.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    wget
    unzip
    helvum
    pavucontrol
    playerctl
    brightnessctl
    inputs.nix-software-center.packages.${pkgs.system}.nix-software-center
    lxqt.lxqt-policykit
    accountsservice
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  networking.nftables.enable = true;

  system.stateVersion = "24.11";
}
