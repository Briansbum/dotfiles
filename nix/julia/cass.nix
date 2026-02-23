{ config, pkgs, ... }:

{
  home.username = "cass";
  home.homeDirectory = "/home/cass";

  home.stateVersion = "25.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    brave
    nautilus
    vlc
    gedit
    eog
    file-roller
    wl-clipboard
  ];

  programs.ghostty = {
    enable = true;
    settings = {
      background-opacity = 0.9;
      background-blur = true;
    };
  };

  programs.fish = {
    enable = true;
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "brave-browser.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "x-scheme-handler/about" = "brave-browser.desktop";
      "x-scheme-handler/unknown" = "brave-browser.desktop";
    };
  };
}
