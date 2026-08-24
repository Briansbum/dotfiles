# Home-manager configuration for alex on sierpinski (Chromebook thin client)
# Console-only profile — no GUI, minimal package set

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

  home.packages = with pkgs; [
    ripgrep
    python3
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

  # No display for pinentry-gnome3, always use curses
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

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
