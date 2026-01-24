{ config, pkgs, inputs, ... }:

{
  imports = [
    ../common/common.nix
    inputs.nixvim.homeModules.nixvim
  ];

  # How does this work in a multi-machine context where I might not provision
  # the user myself?
  home.username = "alex";
  home.homeDirectory = "/home/alex";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Packages to install that don't have a module.
  home.packages = with pkgs; [
    brave
    bitwarden-desktop
    discord
    zig
    gdb
    lshw
    darktable
    imagemagick
    lxmenu-data
    shared-mime-info
    clipse
    wl-clipboard
    tenv
    shellcheck
    python3
    bash
    helm
    jsoncpp
    yq
    tflint
    telegram-desktop
    tree-sitter
    udiskie
    vlc
    vlc-bittorrent
    libraw
    ueberzugpp
    yt-dlp
    gnupg
    pinentry-curses
    pinentry-rofi
    (ffmpeg.override {
    withXcb = true;
    })
    lua
    luarocks
    ripgrep
    heroic
    wf-recorder
    slurp
    rofi
    xwayland-satellite
    mako
    gamescope
    pinta
  ];

  # Config file locations for programs that cannot manage themselves
  xdg.configFile = {
    # "foo".source = ../../config/foo;
    "niri/config.kdl".source = ../../config/niri/config.kdl;
    "starship.toml".source = ../../config/starship.toml;
    "yazi".source = ../../config/yazi;
    # nvim now managed by nixvim - old config at ../../config/nvim for reference
    "rofi".source = ../../config/rofi;
  };

  # NixVim configuration
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    imports = [ ../common/nixvim ];
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        email = "freestone.alex@gmail.com";
        name = "Alex Freestone";
        signingkey = "A0E7C0BF628420C273078074873DF106014C63F7";
      };
      commit = {
        gpgsign = true;
      };
      push = {
        autoSetupRemote = true;
      };
      init = {
        defaultBranch = "main";
      };
    };
  };

  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;
    installVimSyntax = true;
    settings = {
      background-opacity = 0.7;
      background-blur = true;
      background = "#16181a";
      foreground = "#ffffff";
      cursor-color = "#ffffff";
      selection-background = "#3c4048";
      selection-foreground = "#ffffff";

      palette = [
        # cyberdream
        "0=#16181a"
        "1=#ff6e5e"
        "2=#5eff6c"
        "3=#f1ff5e"
        "4=#5ea1ff"
        "5=#bd5eff"
        "6=#5ef1ff"
        "7=#ffffff"
        "8=#3c4048"
        "9=#ff6e5e"
        "10=#5eff6c"
        "11=#f1ff5e"
        "12=#5ea1ff"
        "13=#bd5eff"
        "14=#5ef1ff"
        "15=#ffffff"
      ];
    };
  };

  programs.jq.enable = true;
  programs.obs-studio.enable = true;
  programs.fd.enable = true;
  programs.fzf.enable = true;
  programs.go.enable = true;

  # -----------------------------
  # Programs in this section might have partial configs defined here but
  # they should be considered on-notice while they're getting migrated
  # into their own module/flake. As a result you can find their XDG_CONFIG
  # location higher up in this file
  programs.starship.enable = true;

  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
  };

  # Fish shell configuration - Linux-specific overrides
  programs.fish = {
    interactiveShellInit = ''
      fish_config theme save cyberdream

      # Autojump integration
      test -f ${pkgs.autojump}/share/autojump/autojump.fish; and source ${pkgs.autojump}/share/autojump/autojump.fish
    '';
  };

  # Services with home-manager modules go here
  services.mako = {
    enable = true;
    settings = {
      font = "GoMono Nerd Font 10";
      background-color = "#11092DAA";
      progress-color = "#FFFFFF";
    };
  };

  services.easyeffects.enable = true;
  services.clipse.enable = true;
}
