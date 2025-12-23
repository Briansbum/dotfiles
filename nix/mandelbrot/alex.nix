{ config, pkgs, ... }:

{
  imports = [ ../common/common.nix ];

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
  ];

  # Config file locations for programs that cannot manage themselves
  xdg.configFile = {
    # "foo".source = ../../config/foo;
    "niri/config.kdl".source = ../../config/niri/config.kdl;
    "starship.toml".source = ../../config/starship.toml;
    "fish/conf.d".source = ../../config/fish/conf.d;
    "yazi".source = ../../config/yazi;
    "nvim".source = ../../config/nvim;
    "rofi".source = ../../config/rofi;
  };

  # Config for programs with modules
  programs.fish.enable = true;

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    withRuby = true;
    withPython3 = true;
    withNodeJs = true;
    vimAlias = true;
    viAlias = true;
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        email = "freestone.alex@gmail.com";
        name = "Alex Freestone";
      };
      push = {
        autoSetupRemote = true;
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
      background = "#1e100d";
      foreground = "#f9dcd7";
      cursor-color = "#ffb4a5";
      selection-background = "#8f1200";
      selection-foreground = "#f9dcd7";

      palette = [
        "#1e100d"
        "#e14984"
        "#9bd66e"
        "#dbaa7b"
        "#c76754"
        "#bf9289"
        "#ffb4a5"
        "#abb2bf"
        "#5c6370"
        "#e05f94"
        "#ade086"
        "#e8bf97"
        "#ffc1b0"
        "#bd5c5b"
        "#a16d57"
        "#ffffff"
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

  # Services with home-manager modules go here
  services.mako = {
    enable = true;
    settings = {
      font = "GoMono Nerd Font 10";
      background-color = "#11092DAA";
      progress-color = "#FFFFFF";
    };
  };

  services.easyEffects.enable = true;
  services.clipse.enable = true;
}
