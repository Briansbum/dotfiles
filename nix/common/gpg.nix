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
  # NOTE: do not enable `use-keyboxd` (e.g. via a hand-written ~/.gnupg/common.conf).
  # keyboxd serves the keyring out of a SQLite database, and every pubkey lookup
  # (git signing, encrypt, verify) then contends on "database is locked"
  # (SQLITE_BUSY) whenever gpg runs concurrently. The default pubring.kbx is
  # lock-free for reads and much more reliable. The activation below strips it
  # from machines where it was added manually.
  home.activation.removeKeyboxd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    conf="$HOME/.gnupg/common.conf"
    if [ -f "$conf" ] && grep -q '^use-keyboxd' "$conf"; then
      sed '/^use-keyboxd/d' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
      chmod 600 "$conf"
      ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent || true
      $DRY_RUN_CMD echo "Removed use-keyboxd from ~/.gnupg/common.conf"
    fi
  '';

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
      if pkgs.stdenv.hostPlatform.isDarwin then pkgs.pinentry_mac else pinentry-auto
    );
  };

  systemd.user.sockets.gpg-agent-browser = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
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
