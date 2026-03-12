# System configuration for koch (NAS)
#
# Services: Immich, Grocy, Copyparty, Tailscale, NFS, SMART, btrfs scrub, B2 backups
# No GUI — headless server managed via SSH and Tailscale

{ config, pkgs, inputs, lib, ... }:

{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };

  security.sudo.enable = true;
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "koch";
  time.timeZone = "Europe/London";
  environment.variables.EDITOR = "nvim";

  # ---------------------------------------------------------------------------
  # Users
  # ---------------------------------------------------------------------------

  users.users.alex = {
    isNormalUser = true;
    description = "Alex";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIfEsNDo0qIws3jPsuD9YNlqS+a4/T9Zl5p8TmjGv7UVnYaiDBNU/MSedshMGo9OsRW9Eu7NFVz7b+w3dmj+XNY= alex@AlexF.local"
    ];
  };

  # ---------------------------------------------------------------------------
  # Shell — bash redirects to fish (same pattern as mandelbrot)
  # ---------------------------------------------------------------------------

  programs.bash.interactiveShellInit = ''
    if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
    then
      shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
      exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
    fi
  '';

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
    pinentryPackage = pkgs.pinentry-curses;
  };

  # ---------------------------------------------------------------------------
  # Core services
  # ---------------------------------------------------------------------------

  # Auto-login on tty1 — headless server, physical access implies trust
  services.getty.autologinUser = "alex";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.tailscale.enable = true;
  services.resolved.enable = true;
  services.avahi.enable = true;

  # ---------------------------------------------------------------------------
  # NIC tuning — disable offloading on e1000e
  # The e1000e driver misbehaves with offloading enabled; this matches the
  # Proxmox workaround: ethtool -K eno1 tso off gso off gro off tx off rx off
  # ---------------------------------------------------------------------------

  systemd.services.nic-tuning = {
    description = "Disable offloading on e1000e NIC";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "nic-tuning" ''
        IFACE=$(${pkgs.iproute2}/bin/ip -o link show | ${pkgs.gawk}/bin/awk -F': ' '/state UP/{print $2; exit}')
        if [ -n "$IFACE" ]; then
          ${pkgs.ethtool}/bin/ethtool -K "$IFACE" tso off gso off gro off tx off rx off || true
        fi
      '';
    };
  };

  # ---------------------------------------------------------------------------
  # Storage health
  # ---------------------------------------------------------------------------

  services.smartd = {
    enable = true;
    autodetect = true;
    # Short self-test daily at 2am, long self-test Sundays at 3am
    defaults.monitored = "-a -o on -S on -s (S/../.././02|L/../../7/03)";
  };

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" "/data" ];
  };

  # ---------------------------------------------------------------------------
  # Immich — photo management
  # ---------------------------------------------------------------------------

  services.immich = {
    enable = true;
    port = 2283;
    openFirewall = true;
    mediaLocation = "/data/photos/immich";
    # machine-learning has known NixOS issues — if it fails, set enable = false
    # and use the server without ML, or run ML remotely from mandelbrot
    machine-learning.enable = true;
  };

  # ---------------------------------------------------------------------------
  # Grocy — household management
  # ---------------------------------------------------------------------------

  services.grocy = {
    enable = true;
    hostName = "koch";
    nginx.enableSSL = false; # Tailscale handles encryption
    settings = {
      currency = "GBP";
      culture = "en_GB";
      calendar.firstDayOfWeek = 1; # Monday
    };
  };

  # ---------------------------------------------------------------------------
  # NFS server
  # ---------------------------------------------------------------------------

  services.nfs.server = {
    enable = true;
    exports = ''
      /data/photos         192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
      /data/moving-photos  192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
      /data/state-store    192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
    '';
  };

  # ---------------------------------------------------------------------------
  # B2 backups via rclone
  #
  # Photos sync is bidirectional (pull then push) so it doubles as restore.
  # B2 credentials provided by sops-nix at /run/secrets/.
  # ---------------------------------------------------------------------------

  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";

  sops.secrets."b2_photos_account_id" = {};
  sops.secrets."b2_photos_application_key" = {};

  systemd.services.rclone-photos = {
    description = "Bidirectional photos sync with Backblaze B2";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "rclone-photos-sync" ''
        ACCT=$(cat /run/secrets/b2_photos_account_id)
        KEY=$(cat /run/secrets/b2_photos_application_key)
        RCLONE="${pkgs.rclone}/bin/rclone"
        OPTS="--config /dev/null --transfers 4 --log-level INFO --log-file /var/log/rclone-photos.log"
        REMOTE=":b2,account=$ACCT,key=$KEY:truenas-photos-pool"

        # Pull missing files from B2
        $RCLONE copy "$REMOTE" /data/photos $OPTS
        # Push missing files to B2
        $RCLONE copy /data/photos "$REMOTE" $OPTS
      '';
    };
  };

  systemd.timers.rclone-photos = {
    description = "Hourly photos sync with B2";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };

  systemd.services.immich-db-dump-prep = {
    description = "immich-db-dump runs as a postgres user and can't make its own backup directory";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /data/photos/immich/db-backup";
      ExecStart = "${pkgs.coreutils}/bin/chmod -R 762 /data/photos/immich/db-backup";
    };
  };

  systemd.services.immich-db-dump = {
    description = "Dump Immich PostgreSQL database for backup";
    after = [ "postgresql.service" "immich-db-dump-prep.service" ];
    requires = [ "postgresql.service" "immich-db-dump-prep.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      ExecStart = pkgs.writeShellScript "immich-db-dump" ''
        ${config.services.postgresql.package}/bin/pg_dump immich | ${pkgs.gzip}/bin/gzip > /data/photos/immich/db-backup/immich-dump.sql.gz
      '';
    };
  };

  systemd.timers.immich-db-dump = {
    description = "Daily Immich DB dump";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------

  networking.nftables.enable = true;
  networking.firewall.allowedTCPPorts = [
    22    # SSH
    80    # Grocy (nginx)
    2049  # NFS
    2283  # Immich
  ];

  # ---------------------------------------------------------------------------
  # System packages
  # ---------------------------------------------------------------------------

  environment.systemPackages = with pkgs; [
    age
    sops
    vim
    wget
    htop
    rclone
    smartmontools
    btrfs-progs
    ethtool
    lshw
    tmux
  ];

  # ---------------------------------------------------------------------------
  # State version — do NOT change after initial install
  # ---------------------------------------------------------------------------

  system.stateVersion = "24.11";
}
