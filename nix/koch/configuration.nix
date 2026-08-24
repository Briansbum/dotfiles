# System configuration for koch (NAS)
#
# Services: Immich, Grocy, Tailscale, NFS, SMART, btrfs scrub, B2 backups, Grafana Alloy, GoClaw
# No GUI — headless server managed via SSH and Tailscale

{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
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
    uid = 1000;
    isNormalUser = true;
    description = "Alex";
    extraGroups = [
      "wheel"
      "syncthing"
    ];
    openssh = {
      authorizedKeys.keyFiles = [ ../common/alex-yubikey.pub ];
    };
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
      KbdInteractiveAuthentication = false;
    };
  };

  services.tailscale = {
    enable = true;
    permitCertUid = "traefik";
  };
  services.tailscaleServe = {
    traefik = {
      localPort = 443;
      tsPort = 443;
      tcp = true;
      afterService = "traefik";
    };
  };
  services.resolved.enable = true;
  services.avahi.enable = true;

  # ---------------------------------------------------------------------------
  # DNSControl - a oneshot used by services that have names to run dnscontrol
  # ---------------------------------------------------------------------------

  sops.secrets."dnscontrol_creds_json" = { };

  systemd.services.dnscontrol =
    let
      dnsConfig = pkgs.writeText "dnsconfig.js" ''
        var REG_NONE = NewRegistrar("none");
        var DSP_DESEC = NewDnsProvider("desec");

        D("brians.skin", REG_NONE, DnsProvider(DSP_DESEC), NO_PURGE,
          A("immich.koch", "100.113.219.76"),
          A("grocy.koch", "100.113.219.76"),
          A("chorcy.koch", "100.113.219.76"),
          A("git.koch", "100.113.219.76"),
        );
      '';
    in
    {
      description = "Runs dnscontrol push";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "dnscontrol-push" ''
          	${pkgs.dnscontrol}/bin/dnscontrol push \
          	  --creds ${config.sops.secrets.dnscontrol_creds_json.path} \
                    --config ${dnsConfig};
        '';
      };
    };

  # ---------------------------------------------------------------------------
  # Traefik — reverse proxy with Tailscale TLS
  # Immich is the default service, Grocy under /grocy
  # ---------------------------------------------------------------------------

  sops.secrets."desec_token" = { };

  services.traefik = {
    enable = true;
    environmentFiles = [ config.sops.secrets.desec_token.path ];
    staticConfigOptions = {
      entryPoints.web = {
        address = ":80";
        http.redirections.entryPoint = {
          to = "websecure";
          scheme = "https";
        };
      };
      entryPoints.websecure = {
        address = "localhost:443";
        http.tls.certResolver = "desec";
      };
      certificatesResolvers.tailscale.tailscale = { };
      certificatesResolvers.desec.acme = {
        email = "freestone.alex@gmail.com";
        storage = "/var/lib/traefik/acme.json";
        dnsChallenge = {
          provider = "desec";
          resolvers = [
            "ns1.desec.io:53"
            "ns2.desec.org:53"
          ];
          delayBeforeCheck = "30s";
        };
      };
    };
    dynamicConfigOptions.http = {
      routers = {
        chorcy = {
          rule = "Host(`chorcy.koch.brians.skin`)";
          service = "chorcy";
          tls.certResolver = "desec";
        };
        grocy = {
          rule = "Host(`grocy.koch.brians.skin`)";
          service = "grocy";
          tls.certResolver = "desec";
        };
        immich = {
          rule = "Host(`immich.koch.brians.skin`)";
          service = "immich";
          tls.certResolver = "desec";
        };
      };
      services = {
        immich.loadBalancer.servers = [ { url = "http://localhost:2283"; } ];
        grocy.loadBalancer.servers = [ { url = "http://localhost:2383"; } ];
        chorcy.loadBalancer.servers = [ { url = "http://localhost:2483"; } ];
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
    fileSystems = [
      "/"
      "/data"
    ];
  };

  # ---------------------------------------------------------------------------
  # Immich — photo management
  # ---------------------------------------------------------------------------

  users.users.immich = {
    uid = 996;
  };
  users.groups.immich = {
    gid = 997;
  };

  services.immich = {
    enable = true;
    port = 2283;
    openFirewall = false; # Traefik fronts this
    mediaLocation = "/data/photos/immich";
    # machine-learning has known NixOS issues — if it fails, set enable = false
    # and use the server without ML, or run ML remotely from mandelbrot
    machine-learning.enable = true;
  };

  # Bind-mount external photo directories into Immich's namespace
  systemd.services.immich-server.serviceConfig = {
    BindReadOnlyPaths = [
      "/data/photos/google"
      "/data/photos/Export"
      "/data/photos/Ingest"
      "/data/photos/sync"
    ];
    PrivateUsers = lib.mkForce false;
  };

  # Allow Alloy to read Immich's PostgreSQL for metrics
  services.postgresql.authentication = lib.mkAfter ''
    local immich alloy peer
  '';

  # ---------------------------------------------------------------------------
  # Syncthing - easy file sync
  # ---------------------------------------------------------------------------

  sops.secrets."syncthing_cert" = {
    sopsFile = ./syncthing.yaml;
    owner = "alex";
  };
  sops.secrets."syncthing_key" = {
    sopsFile = ./syncthing.yaml;
    owner = "alex";
  };

  services.syncthing = {
    enable = true;
    cert = config.sops.secrets."syncthing_cert".path;
    key = config.sops.secrets."syncthing_key".path;
    user = "alex";
    group = "syncthing";
    dataDir = config.users.users.alex.home + "/syncthing";
    configDir = config.users.users.alex.home + "/.config/syncthing";
    settings = {
      openDefaultPorts = true;
      localAnnounceEnabled = true;
      devices = {
        doccla-mac = {
          id = "LI4CXJ6-WCQVB7Y-LZNZJYR-XKT3RYB-W7IDWIJ-JQKGHI4-OLJMCKY-ZLX57QU";
        };
        mandelbrot = {
          id = "LIXMZLQ-F5CQCIQ-JN6OLEZ-QUDKAQC-ZAHAPRY-Y76AREC-A7OGEUT-VSGPKQL";
        };
        julia = {
          id = "PCDES7Z-7DYANWV-RGMXFMP-EVAV4MF-5DB4I3M-HEEPXAA-DTRUML4-MFPSBAP";
        };
        pixel10 = {
          id = "KIRCSTT-YWT37YF-BNIFKK2-LRE2Q4V-LRNYPL6-5WVYV6U-PB2XBYN-5CNQCA4";
        };
      };
      folders = {
        "synchspace" = {
          path = "/data/synchspace";
          devices = [
            "doccla-mac"
            "mandelbrot"
            "julia"
            "pixel10"
          ];
          versioning = {
            type = "simple";
            params.keep = "10";
          };
        };
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Grocy — household management
  # ---------------------------------------------------------------------------

  services.grocy = {
    enable = true;
    hostName = "grocy.koch.brians.skin";
    nginx.enableSSL = false;
    dataDir = "/data/grocy/data";
    settings = {
      currency = "GBP";
      culture = "en_GB";
      calendar.firstDayOfWeek = 1; # Monday
    };
  };

  # Move Grocy's nginx to 8080 so Traefik can own 80/443
  services.nginx.virtualHosts."grocy.koch.brians.skin".listen = [
    {
      addr = "127.0.0.1";
      port = 2383;
    }
  ];

  # ---------------------------------------------------------------------------
  # Chorcy — chore chart PWA for Grocy (static bundle served by nginx on :2483,
  # fronted by Traefik at chorcy.koch.brians.skin). Module from the chorcy flake.
  # ---------------------------------------------------------------------------

  services.chorcy.enable = true;

  # ---------------------------------------------------------------------------
  # NFS server
  # ---------------------------------------------------------------------------

  services.nfs.server = {
    enable = true;
    exports = ''
      /data/photos         192.168.1.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=100)
      /data/moving-photos  192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
      /data/state-store    192.168.1.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=100)
    '';
  };

  # Ensure NFS export dirs are owned by alex so the squashed uid=1000 can r/w.
  # Immich's subtree is pinned separately so it stays under the immich service user.
  systemd.tmpfiles.rules = [
    # /data must be root-owned or tmpfiles refuses to descend ("unsafe path transition")
    "d /data               0755 root   root      -"
    # Syncthing runs as alex:syncthing; keep the folder and marker writable.
    "d /data/synchspace    2775 alex   syncthing -"
    "d /data/synchspace/.stfolder 2775 alex syncthing -"
    "d /data/photos        0755 alex   users     -"
    "d /data/photos/immich 0750 immich immich -"
    "Z /data/photos/immich 0750 immich immich -"
    "d /data/grocy/data    0750 grocy  nginx  -"
    "Z /data/grocy/data    0750 grocy  nginx  -"
    "d /data/state-store   0755 alex   users  -"
  ];

  # ---------------------------------------------------------------------------
  # B2 backups via rclone
  #
  # Photos sync is bidirectional (pull then push) so it doubles as restore.
  # B2 credentials provided by sops-nix at /run/secrets/.
  # ---------------------------------------------------------------------------

  sops.secrets."b2_photos_account_id" = { };
  sops.secrets."b2_photos_application_key" = { };

  systemd.services.rclone-photos = {
    description = "Push photos to Backblaze B2";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "rclone-photos-sync" ''
        ACCT=$(cat /run/secrets/b2_photos_account_id)
        KEY=$(cat /run/secrets/b2_photos_application_key)
        RCLONE="${pkgs.rclone}/bin/rclone"
        # --no-traverse: skip listing the remote bucket on each run, avoiding
        # Class C (list) API charges. Safe here because the photo archive is
        # append-only — new files are added daily to a large existing collection.
        OPTS="--config /dev/null --no-traverse --transfers 4 --log-level INFO --log-file /var/log/rclone-photos.log"
        REMOTE=":b2,account=$ACCT,key=$KEY:truenas-photos-pool"

        # Exclude Immich's auto-generated derivatives — regeneratable from
        # originals and not worth the storage or transfer cost.
        $RCLONE copy /data/photos "$REMOTE" $OPTS \
          --exclude "immich/thumbs/**" \
          --exclude "immich/encoded-video/**" \
          --exclude "immich/profile/**"
      '';
    };
  };

  systemd.timers.rclone-photos = {
    description = "Daily photos backup to B2";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
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
    after = [
      "postgresql.service"
      "immich-db-dump-prep.service"
    ];
    requires = [
      "postgresql.service"
      "immich-db-dump-prep.service"
    ];
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
  users.groups.alloy = { };

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
    22 # SSH
    80 # Traefik (HTTP -> HTTPS redirect)
    443 # Traefik (HTTPS)
    8080 # Traefik dashboard
    2049 # NFS
    4317 # OTLP gRPC (Alloy receiver for local services)
    4318 # OTLP HTTP (Alloy receiver for local services)
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
    dnscontrol
    zmx
  ];

  # ---------------------------------------------------------------------------
  # State version — do NOT change after initial install
  # ---------------------------------------------------------------------------

  system.stateVersion = "24.11";
}
