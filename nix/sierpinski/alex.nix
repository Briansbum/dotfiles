# Home-manager configuration for alex on sierpinski (Chromebook thin client)
# Ghostty workstation profile — cage kiosk on tty1, no DE, minimal package set

{
  config,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../common/common.nix
    inputs.nixvim.homeModules.nixvim
  ];

  home.username = "alex";
  home.homeDirectory = "/home/alex";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  machine.agent.primary = "pi";

  home.packages = with pkgs; [
    ripgrep
    yq
    gnupg
    pinentry-curses
    udiskie
  ];

  xdg.configFile = {
    "fish/themes/cyberdream.theme".source = ../../config/fish/themes/cyberdream.theme;
    "starship.toml".source = ../../config/starship.toml;
    "yazi".source = ../../config/yazi;
  };

  # The only display is the ghostty kiosk; curses pinentry draws fine in it and
  # keeps the GTK pinentry closure off the 32GB disk
  services.gpg-agent.pinentry.package = pkgs.pinentry-curses;

  programs.git = {
    enable = true;
    settings = {
      user = {
        email = "freestone.alex@gmail.com";
        name = "Alex Freestone";
        signingkey = "048A9A1A139F42646792C0E39E0B4C28A344E764";
      };
      commit.gpgsign = true;
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
    };
  };

  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    imports = [ ../common/nixvim ];
  };

  programs.jq.enable = true;
  programs.fd.enable = true;
  programs.fzf = {
    enable = true;
    enableFishIntegration = false;
  };
  programs.starship.enable = true;
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    shellWrapperName = "y";
  };

  programs.fish = {
    interactiveShellInit = ''
      set -x __fish_override true
      fish_config theme choose cyberdream
      set -e __fish_override
      test -f ${pkgs.autojump}/share/autojump/autojump.fish; and source ${pkgs.autojump}/share/autojump/autojump.fish
    '';
  };

  # The machine's only GUI: ghostty fullscreen under cage on tty1. Solid
  # background — there is no compositor, so opacity and blur would just be a
  # flat overlay. Exiting the shell hands the VT back to cage, which restarts
  # it fresh.
  programs.ghostty = {
    enable = true;
    enableFishIntegration = false; # fish 4.x handles shell integration natively
    installVimSyntax = true;
    settings = {
      font-family = "GoMono Nerd Font";
      font-size = 12;
      window-decoration = false;
      quit-after-last-window-close = true;

      # cyberdream, same palette as mandelbrot
      background = "#16181a";
      foreground = "#ffffff";
      cursor-color = "#ffffff";
      selection-background = "#3c4048";
      selection-foreground = "#ffffff";

      palette = [
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

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
