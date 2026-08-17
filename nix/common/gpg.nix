{ lib, pkgs, ... }:

let
  # Wayland-friendly pinentry: GNOME3 (gcr) by default, curses when the
  # caller opts in via `PINENTRY_USER_DATA=curses` (e.g. over SSH).
  pinentry-auto = pkgs.writeShellScriptBin "pinentry-auto" ''
    if [ "$PINENTRY_USER_DATA" = "curses" ]; then
      exec ${pkgs.pinentry-curses}/bin/pinentry-curses "$@"
    fi
    exec ${pkgs.pinentry-gnome3}/bin/pinentry-gnome3 "$@"
  '';
in
{
  programs.gpg = {
    enable = true;
    scdaemonSettings.disable-ccid = lib.mkDefault true;
    publicKeys = [
      {
        source = ./alex.asc;
        trust = "ultimate";
      }
    ];
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    enableExtraSocket = true;
    enableFishIntegration = true;
    defaultCacheTtl = 3600;
    defaultCacheTtlSsh = 3600;
    maxCacheTtl = 14400;
    maxCacheTtlSsh = 14400;
    pinentry.package = lib.mkDefault (
      if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pinentry-auto
    );
  };

  systemd.user.sockets.gpg-agent-browser = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "GnuPG cryptographic agent and passphrase cache (access for web browsers)";
      Documentation = "man:gpg-agent(1)";
    };
    Socket = {
      ListenStream = "%t/gnupg/S.gpg-agent.browser";
      FileDescriptorName = "browser";
      Service = "gpg-agent.service";
      SocketMode = "0600";
      DirectoryMode = "0700";
    };
    Install.WantedBy = [ "sockets.target" ];
  };
}
