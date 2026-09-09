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

  # No xdg.mimeApps here: KDE's Default Applications UI writes mimeapps.list,
  # and it must stay mutable so System Settings can manage it. Set Brave as the
  # default browser via System Settings → Apps & Windows → Default Applications.
}
