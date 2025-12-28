{ pkgs, config, ... }:

{
  # Common packages that should be available on all systems
  home.packages = with pkgs; [ ];

  # Shared program configurations
  programs = {
    # Still need to enable more shared config
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
