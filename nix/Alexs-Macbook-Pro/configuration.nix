{ config, pkgs, ... }:

{
  # Set primary user for system defaults
  system.primaryUser = "alex";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System-level packages available to all users
  environment.systemPackages = with pkgs; [
    # Core utilities
    tree
    coreutils
    gnused
    
    # Build tools
    cmake
    ninja
    autoconf
    autoconf-archive
    automake
    ccache
    pkgconf
    nasm
    
    # Development languages & runtimes
    nodejs
    python311
    elixir
    zig
    lua
    luarocks
    openjdk
    leiningen
    maven
    
    # Go tools
    delve
    
    # Version control & Git tools
    gh
    
    # Text processing & CLI tools
    fd
    ripgrep
    fzf
    jq
    yq
    wget
    unzip
    watch
    watchexec
    parallel
    glow
    
    # DevOps & Cloud
    ansible
    azure-cli
    awscli2
    docker
    
    # Kubernetes ecosystem
    kubectl
    kubernetes-helm  
    k9s
    kind
    kubectx
    kubeseal
    kustomize
    minikube
    operator-sdk
    stern
    
    # Infrastructure as Code
    terragrunt
    terraform-docs
    tflint
    tenv  
    
    # Monitoring & Observability
    trivy
    dive
    
    # Security & Secrets
    age
    sops
    gopass
    certbot
    pinentry_mac
    wireguard-tools
    aws-vault
    _1password-cli
    
    # Terminal & Shell
    tmux
    zmx
    starship
    htop
    neovim
    shellcheck
    pay-respects
    
    # Networking
    dnscontrol
    inetutils  # Provides telnet on darwin
    hurl
    
    # Graphics & Build dependencies
    graphviz
    harfbuzz
    qemu
    
    # Other utilities
    uv
    avrdude
    yarn
    steampipe
    buf
    ory  
  ];

  # User configuration
  users.users.alex = {
    name = "alex";
    home = "/Users/alex";
  };

  # Nix configuration
  nix.settings = {
    experimental-features = "nix-command flakes";
    trusted-users = [ "@admin" ];
  };

  # Enable nix-darwin to manage Homebrew
  homebrew = {
    enable = true;
    
    # Automatically update Homebrew and upgrade packages
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";  # Uninstall packages not listed
    };

    # Taps for packages not in nixpkgs
    taps = [
      "andreybleme/lazycontainer"
      "artginzburg/tap"
      "azure/kubelogin"
      "bufbuild/buf"
      "charmbracelet/tap"
      "clojure/tools"
      "danvergara/tools"
      "homebrew/services"
      "omissis/go-jsonschema"
      "ory/tap"
      "osx-cross/arm"
      "osx-cross/avr"
      "qmk/qmk"
      "turbot/tap"
      "atlassian/acli"
    ];

    # Brew formulae (CLI tools not in nixpkgs or better via brew)
    brews = [
      # Custom tap packages
      "lazycontainer"
      "artginzburg/tap/sudo-touchid"
      "charmbracelet/tap/crush"
      "clojure/tools/clojure"
      "omissis/go-jsonschema/go-jsonschema"
      "ory/tap/hydra"
      "qmk/qmk/qmk"
      "atlassian/acli/acli"
      
      # Tools that might need specific versions or macOS integration
      "pam-reattach"  # For tmux Touch ID support
      "fish-lsp"
      "kcat"
      "pixie"
      "pngpaste"
      "pop"
      "helm-docs"
      "terraformer"  # If not available in nixpkgs
      "kubelogin"  # Azure kubelogin from tap
      
    ];

    # GUI Applications (Casks)
    casks = [
      "amethyst"
      "claude"
      "container"
      "ghostty"
      "google-chrome"
      "gpg-suite"
      "k6-studio"
      "spotify"
      "visual-studio-code"
    ];
  };

  # Services
  services.tailscale = {
    enable = true;
  };

  # Steampipe service (local Postgres endpoint for cloud queries)
  launchd.user.agents.steampipe = {
    serviceConfig = {
      Label = "com.turbot.steampipe";
      ProgramArguments = [
        "${pkgs.steampipe}/bin/steampipe"
        "service"
        "start"
        "--foreground"
        "--database-listen"
        "local"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/steampipe.log";
      StandardErrorPath = "/tmp/steampipe.err.log";
    };
  };

  # Fonts
  fonts.packages = with pkgs; [
    (nerd-fonts.go-mono)
  ];

  # Shell configuration
  programs.fish.enable = true;
  programs.zsh.enable = true;  # Keep zsh as fallback

  # Install pre-commit via uv (avoids heavy swift/dotnet dependency chain in nixpkgs)
  system.activationScripts.postActivation.text = ''
    echo "Installing pre-commit via uv..."
    sudo -u alex HOME=/Users/alex ${pkgs.uv}/bin/uv tool install pre-commit --quiet || true
  '';

  # System version
  system.stateVersion = 5;
}
