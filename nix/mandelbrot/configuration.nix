# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, pkgs, inputs, lib, ... }:

with pkgs; let
  patchDesktop = pkg: appName: from: to: lib.hiPrio (
    pkgs.runCommand "$patched-desktop-entry-for-${appName}" {} ''
      ${coreutils}/bin/mkdir -p $out/share/applications
      ${gnused}/bin/sed 's#${from}#${to}#g' < ${pkg}/share/applications/${appName}.desktop > $out/share/applications/${appName}.desktop
      '');
  GPUOffloadApp = pkg: desktopName: patchDesktop pkg desktopName "^Exec=" "Exec=nvidia-offload ";
in
{
  imports = [
    inputs.dankMaterialShell.nixosModules.dank-material-shell
    inputs.dankMaterialShell.nixosModules.greeter
  ];

  nix.settings = {
    substituters = ["https://hyprland.cachix.org"];
    trusted-substituters = ["https://hyprland.cachix.org"];
    trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
    experimental-features = ["nix-command" "flakes"];
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.useOSProber = true;

  security.sudo.enable = true;

  systemd.services = with pkgs; {
    ollama = {
      wantedBy = ["multi-user.target"];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "tailscaled.service" ];

      description = "runs ollama for model serving";

      serviceConfig = {
        ExecStart = "${pkgs.ollama-cuda}/bin/ollama serve";
        User = "alex";
        Restart = "always";
        RestartSec=3;
        Environment= [
          "PATH=$PATH"
          "OLLAMA_HOST=0.0.0.0:11434"
          "__NV_PRIME_RENDER_OFFLOAD=1"
          "__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-GO"
          "__GLX_VENDOR_LIBRARY_NAME=nvidia"
          "__VK_LAYER_NV_optimus=NVIDIA_only"
        ];
      };
    };
    ollama_serve = {
      wantedBy = ["multi-user.target"];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "tailscaled.service" "ollama.service" ];

      description = "serves ollama on the tailnet";

      serviceConfig = {
        ExecStart = "/run/current-system/sw/bin/tailscale serve --https=2021 localhost:11434";
        User = "alex";
        Restart = "always";
        RestartSec=3;
        Environment="PATH=$PATH";
      };
    };
    open-webui = {
      wantedBy = ["multi-user.target"];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "tailscaled.service" "docker.service" ];
      requires = [ "docker.service" ];

      description = "runs open-webui for gptness";

      serviceConfig = {
        ExecStart = "/run/current-system/sw/bin/docker run -p 3000:8080 --add-host=host.docker.internal:host-gateway -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main";
        User = "root";
        Restart = "always";
        RestartSec=3;
      };
    };
    open-webui_serve = {
      wantedBy = ["multi-user.target"];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "tailscaled.service" "open-webui.service" ];

      description = "serves open-webui on the tailnet";

      serviceConfig = {
        ExecStart = "/run/current-system/sw/bin/tailscale serve --https=9091 localhost:3000";
        User = "alex";
        Restart = "always";
        RestartSec=3;
        Environment="PATH=$PATH";
      };
    };
    opencode = {
      wantedBy = ["multi-user.target"];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "tailscaled.service" ];

      description = "runs opencode in web mode";

      serviceConfig = {
        ExecStart = "${pkgs.opencode}/bin/opencode serve --port 4096";
        User = "alex";
        Restart = "always";
        RestartSec = 3;
        Environment = "PATH=$PATH";
      };
    };
    opencode_serve = {
      wantedBy = ["multi-user.target"];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "tailscaled.service" "opencode.service" ];

      description = "serves opencode on the tailnet";

      serviceConfig = {
        ExecStart = "/run/current-system/sw/bin/tailscale serve --https=4096 localhost:4096";
        User = "alex";
        Restart = "always";
        RestartSec = 3;
        Environment = "PATH=$PATH";
      };
    };
  };

  users.users.alex = {
    isNormalUser = true;
    description = "Alex";
    extraGroups = ["wheel" "plugdev"];
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

  services.getty = {
    autologinUser = "alex";
    autologinOnce = true;
  };
#  environment.loginShellInit = ''
#      [[ "$(tty)" == /dev/tty1 ]] && niri
#  '';

  virtualisation.docker.enable = true;

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
    pinentryPackage = wayprompt;
  };

  nixpkgs.config.allowUnfree = true; 

  # Enable OpenGL
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead 
    # of just the bare essentials.
    powerManagement.enable = true;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of 
    # supported GPUs is at: 
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus 
    # Only available from driver 515.43.04+
    open = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  networking.hostName = "mandelbrot"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/London";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  programs.niri.enable = true;
  programs.dank-material-shell = { 
    enable = true; 

    systemd = {
      enable = true;
      restartIfChanged = true;
    };

    greeter = {
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
  };
  
  programs.hyprland = {
    enable = false;
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    config = {
      common.default = ["hyprland" "gtk"];
     # hyprland.default = ["gtk" "hyprland"];
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

  programs.steam = {
    enable = true;
    protontricks.enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # hardware.pulseaudio.enable = true;
  # OR
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
  };

  services.gnome.gnome-keyring.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  # users.users.alice = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
  #   packages = with pkgs; [
  #     tree
  #   ];
  # };

  # programs.firefox.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    cron
    ollama
    ollama-cuda
    opencode
    unzip
    helvum
    pavucontrol
    vulkan-tools
    nvidia-vaapi-driver
    egl-wayland
    playerctl
    brightnessctl
    wayprompt
    btop-cuda
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        # Shows battery charge of connected devices on supported
        # Bluetooth adapters. Defaults to 'false'.
        Experimental = true;
        # When enabled other devices can connect faster to us, however
        # the tradeoff is increased power consumption. Defaults to
        # 'false'.
        FastConnectable = true;
      };
      Policy = {
        # Enable all controllers when they are found. This includes
        # adapters present on start as well as adapters that are plugged
        # in later on. Defaults to 'true'.
        AutoEnable = true;
      };
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  networking.nftables.enable = true;
  networking.firewall.allowedTCPPorts = [ 11434 8554 3923 4096 ];
  networking.firewall.allowedUDPPorts = [ 8554 16261 16262 ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11"; # Did you read the comment?

}

