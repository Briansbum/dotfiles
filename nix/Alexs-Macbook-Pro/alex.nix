{ config, pkgs, ... }:

{
  imports = [ ../common/common.nix ];

  # User info
  home.username = "alex";
  home.homeDirectory = "/Users/alex";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  home.stateVersion = "25.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # macOS-specific packages that aren't in system config
  home.packages = with pkgs; [
    # Add any user-specific packages here
  ];

  # Config file locations for programs that cannot manage themselves
  xdg.configFile = {
    # Shared configs
    "starship.toml".source = ../../config/starship.toml;
    "fish/conf.d".source = ../../config/fish/conf.d;
    "fish/config.fish".source = ../../config/fish/config.fish;
    "fish/functions".source = ../../config/fish/functions;
    "fish/completions".source = ../../config/fish/completions;
    "fish/fish_plugins".source = ../../config/fish/fish_plugins;
    "yazi".source = ../../config/yazi;
    "nvim".source = ../../config/nvim;
    
    # macOS-specific configs
    # ghostty is managed via programs.ghostty module below
    "zed/settings.json".source = ../../config/zed/settings.json;
    "gh/config.yml".source = ../../config/gh/config.yml;
    "gopass/config".source = ../../config/gopass/config;
    "argocd/config".source = ../../config/argocd/config;
    "thefuck/settings.py".source = ../../config/thefuck/settings.py;
    
    # Note: htop, wireshark configs are runtime state - not managed
    # Note: spotifyd, spotify-tui, opencode, op configs have secrets - not managed
  };

  # Config for programs with modules
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
    userName = "Alex Freestone";
    userEmail = "freestone.alex@gmail.com";
    extraConfig = {
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
    # Settings managed via home-manager module (alternative to config file)
    settings = {
      background-opacity = 0.7;
      background-blur = true;
      background = "#1e100d";
      foreground = "#f9dcd7";
      cursor-color = "#ffb4a5";
      selection-background = "#8f1200";
      selection-foreground = "#f9dcd7";

      palette = [
        "1=#1e100d"
        "2=#e14984"
        "3=#9bd66e"
        "4=#dbaa7b"
        "5=#c76754"
        "6=#bf9289"
        "7=#ffb4a5"
        "8=#abb2bf"
        "9=#5c6370"
        "10=#e05f94"
        "11=#ade086"
        "12=#e8bf97"
        "13=#ffc1b0"
        "14=#bd5c5b"
        "15=#a16d57"
        "16=#ffffff"
      ];
    };
  };

  programs.jq.enable = true;
  programs.fd.enable = true;
  programs.fzf.enable = true;
  programs.go.enable = true;

  # Starship prompt
  programs.starship.enable = true;

  # Yazi file manager
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
  };

  # Fish shell configuration
  programs.fish = {
    enable = true;
    # Fish plugins and configuration are handled via xdg.configFile above
  };

  # Tmux configuration
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    keyMode = "vi";
    customPaneNavigationAndResize = true;
    escapeTime = 0;
    historyLimit = 50000;
  };
}
