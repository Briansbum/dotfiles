# Home-manager configuration for alex on koch (NAS)
# Minimal server profile — no GUI, no desktop services

{ config, pkgs, inputs, ... }:

{
  imports = [
    ../common/common.nix
    inputs.nixvim.homeModules.nixvim
  ];

  home.username = "alex";
  home.homeDirectory = "/home/alex";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # Server-only packages — no GUI apps
  home.packages = with pkgs; [
    lshw
    shellcheck
    python3
    bash
    yq
    gnupg
    pinentry-curses
    ripgrep
    
    # Add nix-openclaw
    inputs.nix-openclaw.packages.${pkgs.system}.openclaw
  ];

  xdg.configFile = {
    "fish/themes/cyberdream.theme".source = ../../config/fish/themes/cyberdream.theme;
    "starship.toml".source = ../../config/starship.toml;
    "yazi".source = ../../config/yazi;
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        email = "freestone.alex@gmail.com";
        name = "Alex Freestone";
        signingkey = "A0E7C0BF628420C273078074873DF106014C63F7";
      };
      commit.gpgsign = true;
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
    };
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
  };

  programs.fish = {
    interactiveShellInit = ''
      set -x __fish_override true
      fish_config theme choose cyberdream
      set -e __fish_override
      test -f ${pkgs.autojump}/share/autojump/autojump.fish; and source ${pkgs.autojump}/share/autojump/autojump.fish
    '';
  };

  services.ssh-agent = {
    enable = true;
    enableFishIntegration = true;
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
