{ config, pkgs, lib, ... }:

let
  # Create custom CSS for gtkgreet that matches your hyprlock aesthetic
  gtkgreet-css = pkgs.writeText "gtkgreet.css" ''
    /* Match hyprlock's dark aesthetic */
    window {
      background-image: url("${../../images/omnium.png}");
      background-size: cover;
      background-position: center;
    }
    
    /* Main container styling to match hyprlock's boxes */
    #window {
      background-color: rgba(10, 10, 10, 0.9);
      padding: 20px;
      border-radius: 0px;
    }
    
    /* Body and text styling */
    #body {
      background-color: transparent;
      color: rgba(216, 222, 233, 0.80);
      font-family: "Go Mono", monospace;
    }
    
    /* Clock styling to match hyprlock */
    #clock {
      color: rgba(10, 10, 10, 0.75);
      font-family: "Go Mono", monospace;
      font-size: 40px;
      margin-bottom: 10px;
    }
    
    /* Input fields to match hyprlock */
    #input, #inputbox {
      background-color: rgba(10, 10, 10, 0.9);
      color: rgb(200, 200, 200);
      font-family: "Go Mono", monospace;
      border: none;
      padding: 15px;
      margin: 5px;
      min-width: 320px;
      min-height: 55px;
    }
    
    /* Buttons */
    button {
      background-color: rgba(10, 10, 10, 0.9);
      color: rgba(216, 222, 233, 0.80);
      border: none;
      padding: 15px 30px;
      font-family: "Go Mono", monospace;
      margin: 5px;
    }
    
    button:hover {
      background-color: rgba(30, 30, 30, 0.9);
    }
    
    /* Labels */
    label {
      color: rgba(10, 10, 10, 0.75);
      font-family: "Go Mono", monospace;
    }
  '';

  # Sway config for running gtkgreet
  greetd-sway-config = pkgs.writeText "greetd-sway-config" ''
    # Set background
    output * bg ${../../images/omnium.png} fill
    
    # Remove window borders
    default_border none
    
    # Run gtkgreet and exit sway when done
    exec "${pkgs.greetd.gtkgreet}/bin/gtkgreet -l -s ${gtkgreet-css}; swaymsg exit"
    
    # Allow gtkgreet to work properly
    for_window [app_id=".*"] inhibit_idle fullscreen
  '';
in
{
  # Disable SDDM
  services.displayManager.sddm.enable = false;
  
  # Enable greetd with gtkgreet
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # Use cage to run gtkgreet - simpler than sway and perfect for single-app kiosk mode
        command = "${pkgs.cage}/bin/cage -s -- ${pkgs.greetd.gtkgreet}/bin/gtkgreet -l -s ${gtkgreet-css}";
        user = "greeter";
      };
    };
  };

  # Create greeter user
  users.users.greeter = {
    isSystemUser = true;
    group = "greeter";
    home = "/var/lib/greeter";
    createHome = true;
    extraGroups = [ "video" "input" ];
  };
  
  users.groups.greeter = {};

  # Set up session environments
  environment.etc."greetd/environments".text = ''
    Hyprland
  '';

  # Required packages
  environment.systemPackages = with pkgs; [
    cage
    greetd.greetd
    greetd.gtkgreet
  ];

  # PAM configuration for greetd
  security.pam.services.greetd = {
    enableGnomeKeyring = true;
  };

  # Make sure GTK can find the Go Mono font
  fonts.packages = with pkgs; [
    nerd-fonts.go-mono
  ];
}
