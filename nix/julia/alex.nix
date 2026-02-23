{ config, pkgs, inputs, ... }:

{
  imports = [
    ../common/common.nix
    inputs.nixvim.homeModules.nixvim
  ];

  home.username = "alex";
  home.homeDirectory = "/home/alex";

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
    wf-recorder
    slurp
    rofi
    xwayland-satellite
    mako
    pinta
    uv
  ];

  # Config file locations for programs that cannot manage themselves
  xdg.configFile = {
    "fish/themes/cyberdream.theme".source = ../../config/fish/themes/cyberdream.theme;
    "niri/config.kdl".source = ../../config/niri/config.kdl;
    "starship.toml".source = ../../config/starship.toml;
    "yazi".source = ../../config/yazi;
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
    enableFishIntegration = false;
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
  programs.fzf = {
    enable = true;
    enableFishIntegration = false;
  };
  programs.go.enable = true;

  programs.starship.enable = true;

  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
  };

  # Fish shell configuration - Linux-specific overrides
  programs.fish = {
    interactiveShellInit = ''
      # Apply cyberdream theme (fish 4.3+ style)
      # __fish_override bypasses the "Overwrite your current theme?" prompt
      set -x __fish_override true
      fish_config theme choose cyberdream
      set -e __fish_override

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
