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
    mtr
    
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
    pre-commit
    
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
    argocd
    azure-cli
    awscli
    docker
    
    # Kubernetes ecosystem
    kubectl
    kubernetes-helm  # Renamed from helm on darwin
    k9s
    kind
    kubectx
    kubeseal
    kustomize
    minikube
    operator-sdk
    stern  # Multi pod and container log tailing
    
    # Infrastructure as Code
    opentofu
    terragrunt
    terraform-docs
    tflint
    packer
    tenv  # Replaces tfenv - handles terraform/terragrunt/opentofu versions
    
    # Database & Data tools
    mysql80
    jsonnet-bundler
    
    # Monitoring & Observability
    # grafana-agent  # Not available in nixpkgs for darwin
    trivy
    dive
    
    # Security & Secrets
    gopass
    certbot
    pinentry_mac
    wireguard-tools
    aws-vault
    bitwarden-cli
    _1password-cli
    
    # Terminal & Shell
    tmux
    starship
    htop
    neovim
    newsboat
    irssi
    lynx
    shellcheck
    # thefuck  # Removed from nixpkgs, use pay-respects instead
    pay-respects
    # Note: fish and autojump managed via home-manager in common.nix
    
    # Networking
    dnscontrol
    inetutils  # Provides telnet on darwin
    hurl
    
    # Graphics & Build dependencies
    graphviz
    harfbuzz
    qemu
    # qt6.full  # Removed from nixpkgs, use individual packages if needed
    
    # Other utilities
    uv
    avrdude
    yarn
    
    # Tools from analysis
    steampipe
    buf
    # dblab  # Broken build on darwin
    ory  # Ory CLI
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
      "sst/tap"
      "turbot/tap"
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
      "sst/tap/opencode"
      
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
      
      # Services (no nix-darwin modules yet)
      {
        name = "ollama";
        restart_service = "changed";
      }
      {
        name = "spotifyd";
        restart_service = "changed";
      }
      "spotify-tui"
    ];

    # GUI Applications (Casks)
    casks = [
      "amethyst"
      "claude"
      "container"
      "ghostty"
      "gimp"
      "google-chrome"
      "gpg-suite"
      "jordanbaird-ice"
      "k6-studio"
      "qmk-toolbox"
      "spotify"
      "visual-studio-code"
      "vlc"
      "wireshark"
      "zed"
    ];
  };

  # Services
  services.tailscale = {
    enable = true;
  };

  # Fonts
  fonts.packages = with pkgs; [
    (nerd-fonts.go-mono)
  ];

  # Shell configuration
  programs.fish.enable = true;
  programs.zsh.enable = true;  # Keep zsh as fallback

  # System version
  system.stateVersion = 5;
}
