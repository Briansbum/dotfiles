{ pkgs, config, ... }:

{
  # Shared configuration between macOS and Linux systems
  
  # Common packages that should be available on all systems
  home.packages = with pkgs; [
    # Add packages here that you want on both Linux and macOS
    # Most packages are platform-specific and defined in the respective alex.nix files
  ];

  # Shared program configurations
  programs = {
    # Git config is platform-specific due to potential email/signing differences
    # Define in each alex.nix instead
    
    # These can be shared
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };

  # Shared environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
