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

  # nix-openclaw secret values - each secret is stored in secrets.yaml as key-value pairs
  # openclaw_gateway_token: ENC[AES256_GCM,data:YOUR_ENCRYPTED_TOKEN,iv:RANDOM_IV,tag:TAG,type:str]
  # openclaw_telegram_token: ENC[AES256_GCM,data:YOUR_ENCRYPTED_TELEGRAM_TOKEN,iv:RANDOM_IV,tag:TAG,type:str]
  # openclaw_openrouter_key: ENC[AES256_GCM,data:YOUR_ENCRYPTED_OPENROUTER_KEY,iv:RANDOM_IV,tag:TAG,type:str]
  sops.secrets."openclaw_gateway_token" = {
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
    restartUnits = [ "nix-openclaw.service" ];
  };
  sops.secrets."openclaw_telegram_token" = {
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
    restartUnits = [ "nix-openclaw.service" ];
  };
  sops.secrets."openclaw_openrouter_key" = {
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
    restartUnits = [ "nix-openclaw.service" ];
  };

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

  users.users.openclaw = {
    isSystemUser = true;
    group = "openclaw";
  };
  users.groups.openclaw = {};

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
  # DNSControl - a oneshot used by services that have names to run dnscontrol
  # ---------------------------------------------------------------------------

  sops.secrets."dnscontrol_creds_json" = {};

  systemd.services.dnscontrol = let
    dnsConfig = pkgs.writeText "dnsconfig.js" ''
    var REG_NONE = NewRegistrar("none");
    var DSP_DESEC = NewDnsProvider("desec");
    
    D("brians.skin", REG_NONE, DnsProvider(DSP_DESEC), NO_PURGE,
      CNAME("immich.koch", "koch.tuxedo-burbot.ts.net."),
      CNAME("grocy.koch", "koch.tuxedo-burbot.ts.net."),
    );
    '';
  in {
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

  sops.secrets."desec_token" = {};

  services.traefik = {
    enable = true;
    environmentFiles = [config.sops.secrets.desec_token.path];
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
        http.tls.certResolver = "desec";
      };
      certificatesResolvers.tailscale.tailscale = {};
      certificatesResolvers.desec.acme = {
        email = "freestone.alex@gmail.com";
        storage = "/var/lib/traefik/acme.json";
	dnsChallenge = {
	  provider = "desec";
          resolvers = ["ns1.desec.io:53" "ns2.desec.org:53"];
          delayBeforeCheck = "30s";
        };
      };
    };
    dynamicConfigOptions.http = {
      routers = {
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
        immich.loadBalancer.servers = [{ url = "http://localhost:2283"; }];
        grocy.loadBalancer.servers = [{ url = "http://localhost:2383"; }];
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
    hostName = "grocy.koch.brians.skin";
    nginx.enableSSL = false;
    settings = {
      currency = "GBP";
      culture = "en_GB";
      calendar.firstDayOfWeek = 1; # Monday
    };
  };

  # Move Grocy's nginx to 8080 so Traefik can own 80/443
  services.nginx.virtualHosts."grocy.koch.brians.skin".listen = [{ addr = "127.0.0.1"; port = 2383; }];

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
    8080  # Traefik dashboard
    2049  # NFS
    4317  # OTLP gRPC (Alloy receiver for local services)
    4318  # OTLP HTTP (Alloy receiver for local services)
  ];

  # ---------------------------------------------------------------------------
  # nix-openclaw - AI Assistant with external comms only and strong isolation
  # ---------------------------------------------------------------------------
  
  # Create a systemd user service with strong isolation for nix-openclaw
  systemd.services.nix-openclaw = {
    description = "OpenClaw AI Assistant (isolated)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    environment = {
      # This variable will be overridden by the EnvironmentFile below
      # but we include it here as a fallback and for documentation
      OPENCLAW_GATEWAY_TOKEN = "placeholder_replaced_by_secret";
      # Don't expose any ports - external comms only
      OPENCLAW_NO_SERVER = "1";
    };
    
    serviceConfig = {
      # Run as dedicated user with minimal privileges
      DynamicUser = false;
      User = "openclaw";
      Group = "openclaw";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      MemoryDenyWriteExecute = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX";
      RestrictNamespaces = true;
      RestrictRealtime = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      CapabilityBoundingSet = "";
      RuntimeDirectory = "openclaw";
      RuntimeDirectoryMode = "0750";
      Slice = "openclaw.slice";
      
      # Resource limits
      MemoryMax = "2G";
      CPUQuota = "200%";
      
      # Service execution
      Type = "simple";
      ExecStart = "${inputs.nix-openclaw.packages.${pkgs.system}.openclaw}/bin/openclaw gateway";
      Restart = "on-failure";
      RestartSec = "10s";
      
      # Secrets setup - creates a file with environment variables from the secrets
      # Format of the environment file will be:
      # OPENCLAW_GATEWAY_TOKEN=your_token_value
      # OPENAI_API_KEY=your_openrouter_key (OpenRouter uses the OpenAI API format)
      # OPENAI_API_BASE=https://openrouter.ai/api/v1
      # OPENCLAW_TELEGRAM_BOT_TOKEN=your_telegram_token
      ExecStartPre = pkgs.writeShellScript "prepare-openclaw-env" ''
        mkdir -p /run/openclaw
        echo "OPENCLAW_GATEWAY_TOKEN=$(cat ${config.sops.secrets.openclaw_gateway_token.path})" > /run/openclaw/env
        echo "OPENAI_API_KEY=$(cat ${config.sops.secrets.openclaw_openrouter_key.path})" >> /run/openclaw/env
        echo "OPENAI_API_BASE=https://openrouter.ai/api/v1" >> /run/openclaw/env
        echo "OPENCLAW_TELEGRAM_BOT_TOKEN=$(cat ${config.sops.secrets.openclaw_telegram_token.path})" >> /run/openclaw/env
        chmod 400 /run/openclaw/env
      '';
      EnvironmentFile = "-/run/openclaw/env";
    };
  };

  systemd.slices.openclaw = {
    description = "OpenClaw isolated slice";
    sliceConfig = {
      MemoryMax = "32G";
      CPUQuota = "200%";
    };
  };

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
  ];

  # ---------------------------------------------------------------------------
  # State version — do NOT change after initial install
  # ---------------------------------------------------------------------------

  system.stateVersion = "24.11";
}
