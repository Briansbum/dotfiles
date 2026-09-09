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
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  security.sudo.enable = true;

  # sops values show up at /run/secrets/
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.keyFile = config.users.users.alex.home + "/.config/sops/age/keys.txt";

  users.users.alex = {
    uid = 1000;
    isNormalUser = true;
    description = "Alex";
    extraGroups = [
      "wheel"
      "plugdev"
      "networkmanager"
      "video"
      "syncthing"
    ];
  };

  users.users.cass = {
    isNormalUser = true;
    description = "Cass";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "syncthing"
    ];
  };

  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.devmon.enable = true;
  services.tailscale.enable = true;
  services.avahi.enable = true;
  services.playerctld.enable = true;
  services.resolved.enable = true;
  services.thermald.enable = true;
  services.power-profiles-daemon.enable = true;
  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    LidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend-then-hibernate";
    HandleLidSwitchDocken = "suspend-then-hibernate";
  };

  services.upower = {
    enable = true;
    percentageLow = 20;
    percentageCritical = 7;
    percentageAction = 3;
    criticalPowerAction = "Hibernate";
  };

  services.mullvad-vpn = {
    enable = true;
    gui.enable = true;
  };

  sops.secrets."syncthing_cert" = {
    owner = "alex";
  };
  sops.secrets."syncthing_key" = {
    owner = "alex";
  };

  services.syncthing = {
    enable = true;
    cert = config.sops.secrets."syncthing_cert".path;
    key = config.sops.secrets."syncthing_key".path;
    dataDir = "/home/alex";
    user = "alex";
    group = "users";
    settings = {
      openDefaultPorts = true;
      localAnnounceEnabled = true;
      devices = {
        koch = {
          id = "EWHGTJQ-G23E4XW-SXO3YIQ-5TBIFZH-L4IEKDQ-BWCHVNR-EIS5FZN-H6HUOQA";
          addresses = [
            "tcp://koch:22000"
            "tcp://100.113.219.76:22000"
          ];
        };
      };
      folders = {
        "synchspace" = {
          devices = [ "koch" ];
          path = "~/synchspace";
          versioning = {
            type = "simple";
            params.keep = "10";
          };
        };
      };
    };
  };

  # Fingerprint reader (Framework 13 Goodix MOC sensor)
  services.fprintd.enable = true;

  # cass has a fingerprint enrolled, so LightDM's login PAM substack waits for
  # a scan instead of accepting the password promptly. Skip only the fprintd
  # rule for cass; alex retains fingerprint login and sudo authentication.
  #
  # This uses the experimental PAM rules API. Keep the order relative to the
  # built-in fprintd rule so NixOS changes cannot silently reorder the guard.
  security.pam.services.login.rules.auth.skipFprintForCass = {
    enable = config.services.fprintd.enable;
    order = config.security.pam.services.login.rules.auth.fprintd.order - 10;
    control = "[success=1 default=ignore]";
    modulePath = "${config.security.pam.package}/lib/security/pam_succeed_if.so";
    args = [
      "quiet_success"
      "user"
      "="
      "cass"
    ];
  };

  # Firmware updates (needed for fingerprint sensor firmware)
  services.fwupd.enable = true;

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

  programs.steam = {
    enable = true;
    protontricks.enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
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

  # LightDM — dm-tool switch-to-greeter lets us start a login screen on a free VT
  # (greetd can't) so users can switch sessions without logging anyone out.
  services.xserver.displayManager.lightdm = {
    enable = true;
    greeters.gtk.enable = true;
  };
  # No forced default: LightDM remembers a session per user (Niri for alex,
  # Plasma for cass) instead of writing one session into AccountsService for all.
  services.displayManager.defaultSession = null;

  services.desktopManager.plasma6.enable = true;

  # DMS is installed as a user unit for graphical-session.target; only run it
  # in a Niri session so it doesn't fight Plasma's shell on cass's desktop.
  systemd.user.services.dms.unitConfig.ConditionEnvironment = "XDG_CURRENT_DESKTOP=niri";

  # Portal implementations and routing come from the enabled desktop modules:
  # Niri adds the GNOME/GTK portals and niri-portals.conf; Plasma adds the KDE
  # and GTK portals. XDG_CURRENT_DESKTOP selects the right one per session.
  xdg.portal.enable = true;
  xdg.portal.xdgOpenUsePortal = true;

  boot.kernelParams = [
    "resume_offset=2047"
    "mem_sleep_default=deep"
  ];
  boot.resumeDevice = "/dev/disk/by-uuid/851c22a2-4127-4a0d-983d-f6da6525b82b";
  boot.initrd.systemd.enable = true;

  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "30m";
    SuspendState = "mem";
  };

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024; # 16GB in MiB
    }
  ];

  # Session launchers (Niri, Plasma) set XDG_CURRENT_DESKTOP and
  # XDG_SESSION_TYPE themselves; forcing them machine-wide would mislabel
  # cass's Plasma session as Niri.
  environment.sessionVariables = {
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
    crosspipe
    pavucontrol
    playerctl
    brightnessctl
    inputs.nix-software-center.packages.${pkgs.stdenv.hostPlatform.system}.nix-software-center
    lxqt.lxqt-policykit
    accountsservice
    libthai
    pango
    harfbuzz
    yubikey-manager
    zmx
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
