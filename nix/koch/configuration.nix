# System configuration for koch (NAS)
#
# Services: Immich, Grocy, Tailscale, NFS, SMART, btrfs scrub, B2 backups, Grafana Alloy
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

  # sops values show up at /run/secrets/
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";

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

  services.tailscale = {
    enable = true;
    permitCertUid = "traefik";
  };
  services.resolved.enable = true;
  services.avahi.enable = true;

  # ---------------------------------------------------------------------------
  # Traefik — reverse proxy with Tailscale TLS
  # Immich is the default service, Grocy under /grocy
  # ---------------------------------------------------------------------------

  services.traefik = {
    enable = true;
    staticConfigOptions = {
      entryPoints.web = {
        address = ":80";
        http.redirections.entryPoint = {
          to = "websecure";
          scheme = "https";
        };
      };
      entryPoints.websecure = {
        address = ":443";
        http.tls.certResolver = "tailscale";
      };
      certificatesResolvers.tailscale.tailscale = {};
    };
    dynamicConfigOptions.http = {
      routers = {
        grocy = {
          rule = "Host(`koch.tuxedo-burbot.ts.net`) && PathPrefix(`/grocy`)";
          service = "grocy";
          priority = 20;
          tls.certResolver = "tailscale";
        };
        immich = {
          rule = "Host(`koch.tuxedo-burbot.ts.net`)";
          service = "immich";
          priority = 10;
          tls.certResolver = "tailscale";
        };
      };
      services = {
        immich.loadBalancer.servers = [{ url = "http://localhost:2283"; }];
        grocy.loadBalancer.servers = [{ url = "http://localhost:8080"; }];
      };
    };
  };

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
    openFirewall = false; # Traefik fronts this
    mediaLocation = "/data/photos/immich";
    # machine-learning has known NixOS issues — if it fails, set enable = false
    # and use the server without ML, or run ML remotely from mandelbrot
    machine-learning.enable = true;
  };

  # Allow Alloy to read Immich's PostgreSQL for metrics
  services.postgresql.authentication = lib.mkAfter ''
    local immich alloy peer
  '';

  # ---------------------------------------------------------------------------
  # Grocy — household management
  # ---------------------------------------------------------------------------

  services.grocy = {
    enable = true;
    hostName = "koch";
    nginx.enableSSL = false;
    settings = {
      currency = "GBP";
      culture = "en_GB";
      calendar.firstDayOfWeek = 1; # Monday
    };
  };

  # Move Grocy's nginx to 8080 so Traefik can own 80/443
  services.nginx.virtualHosts."koch".listen = [{ addr = "127.0.0.1"; port = 8080; }];

  # Tell Grocy it lives under /grocy
  services.phpfpm.pools.grocy.phpEnv = {
    GROCY_BASE_PATH = "/grocy";
    GROCY_BASE_URL = "/grocy";
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
  # Grafana Alloy — system metrics + journal logs -> Grafana Cloud
  # Also accepts OTLP from local services (Immich, microvms, etc.)
  # ---------------------------------------------------------------------------

  # secrets show up at /run/secrets
  sops.secrets."alloy_env" = {
    owner = "alloy";
    group = "alloy";
    mode = "0440";
    restartUnits = [ "alloy.service" ];
  };

  users.users.alloy = {
    isSystemUser = true;
    group = "alloy";
    extraGroups = [ "systemd-journal" ];
  };
  users.groups.alloy = {};

  services.alloy = {
    enable = true;
    configPath = "/etc/alloy";
    environmentFile = config.sops.secrets.alloy_env.path;
    extraFlags = [
      "--stability.level=generally-available"
      "--server.http.listen-addr=127.0.0.1:12345"
      "--disable-reporting"
    ];
  };

  systemd.services.alloy.serviceConfig.DynamicUser = lib.mkForce false;
  systemd.services.alloy.serviceConfig.User = lib.mkForce "alloy";
  systemd.services.alloy.serviceConfig.Group = lib.mkForce "alloy";

  environment.etc."alloy/config.alloy" = {
    source = ./alloy-config.alloy;
    mode = "0644";
  };

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------

  networking.nftables.enable = true;
  networking.firewall.allowedTCPPorts = [
    22    # SSH
    80    # Traefik (HTTP -> HTTPS redirect)
    443   # Traefik (HTTPS)
    2049  # NFS
    4317  # OTLP gRPC (Alloy receiver for local services)
    4318  # OTLP HTTP (Alloy receiver for local services)
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
