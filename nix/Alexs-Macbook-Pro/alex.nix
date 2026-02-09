{ config, pkgs, inputs, ... }:

{
  imports = [
    ../common/common.nix
    inputs.nixvim.homeModules.nixvim
  ];

  # User info
  home.username = "alex";
  home.homeDirectory = "/Users/alex";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  home.stateVersion = "25.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # macOS-specific packages that aren't in system config
  home.packages = with pkgs; [
    # Add any user-specific packages here
  ];

  # Config file locations for programs that cannot manage themselves
  xdg.configFile = {
    # Shared configs
    "starship.toml".source = ../../config/starship.toml;
    "yazi".source = ../../config/yazi;
    "fish/themes/cyberdream.theme".source = ../../config/fish/themes/cyberdream.theme;
    # nvim now managed by nixvim - old config at ../../config/nvim for reference
    
    # macOS-specific configs
    "ghostty/config".source = ../../config/ghostty/macos-config;
    "zed/settings.json".source = ../../config/zed/settings.json;
    "gh/config.yml".source = ../../config/gh/config.yml;
    "gopass/config".source = ../../config/gopass/config;
    "argocd/config".source = ../../config/argocd/config;
    "thefuck/settings.py".source = ../../config/thefuck/settings.py;
    
    # Note: htop, wireshark configs are runtime state - not managed
    # Note: spotifyd, spotify-tui, opencode, op configs have secrets - not managed
  };

  # NixVim configuration
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    imports = [ ../common/nixvim ];
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Alex Freestone";
        email = "freestone.alex@gmail.com";
        signingkey = "A0E7C0BF628420C273078074873DF106014C63F7";
      };
      commit = {
        gpgsign = true;
      };
      push = {
        autoSetupRemote = true;
      };
      init = {
        defaultBranch = "main";
      };
    };
  };

  programs.ghostty = {
    enable = false;  # Ghostty on macOS is installed via Homebrew cask
    enableFishIntegration = false;
    installVimSyntax = true;
    # Settings managed via home-manager module (alternative to config file)
    settings = {
      background-opacity = 0.7;
      background-blur = true;
      background = "#1e100d";
      foreground = "#f9dcd7";
      cursor-color = "#ffb4a5";
      selection-background = "#8f1200";
      selection-foreground = "#f9dcd7";

      palette = [
        "1=#1e100d"
        "2=#e14984"
        "3=#9bd66e"
        "4=#dbaa7b"
        "5=#c76754"
        "6=#bf9289"
        "7=#ffb4a5"
        "8=#abb2bf"
        "9=#5c6370"
        "10=#e05f94"
        "11=#ade086"
        "12=#e8bf97"
        "13=#ffc1b0"
        "14=#bd5c5b"
        "15=#a16d57"
        "16=#ffffff"
      ];
    };
  };

  programs.jq.enable = true;
  programs.fd.enable = true;
  programs.fzf.enable = true;
  programs.go.enable = true;

  # Starship prompt
  programs.starship.enable = true;

  # Yazi file manager
  programs.yazi = {
    enable = true;
    enableFishIntegration = false;  # Managed manually via fish config files
  };

  # Claude Code
  programs.claude-code = {
    enable = true;
    enableMcpIntegration = true;
  };
  
  # MCP Servers
  programs.mcp = {
    enable = true;
    servers = {
      grafana = {
        type = "local";
        command = [
          "/Users/alex/go/bin/mcp-grafana"
        ];
        environment = {
          GRAFANA_URL = "https://doccla.grafana.net";
          GRAFANA_API_KEY = "{env:GRAFANA_API_KEY}";
        };
      };
      nixos = {
        type = "local";
        command = [
          "nix"
          "run"
          "github:utensils/mcp-nixos"
          "--"
        ];
      };
      "awslabs.aws-documentation-mcp-server" = {
        type = "local";
        command = [
          "uvx"
          "awslabs.aws-documentation-mcp-server@latest"
        ];
        environment = {
          FASTMCP_LOG_LEVEL = "ERROR";
          AWS_DOCUMENTATION_PARTITION = "aws";
          MCP_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
        };
      };
      atlassian = {
        type = "remote";
        url = "https://mcp.atlassian.com/v1/mcp";
      };
    };
  };

  # Fish shell configuration - macOS-specific overrides
  programs.fish = {
    shellInit = ''
      # Apply cyberdream theme (fish 4.3+ style)
      # __fish_override bypasses the "Overwrite your current theme?" prompt
      set -x __fish_override true
      fish_config theme choose cyberdream
      set -e __fish_override

      # Homebrew paths
      fish_add_path -p /opt/homebrew/bin
      fish_add_path -p /opt/homebrew/opt/coreutils/libexec/gnubin
      
      # Bun
      set --export BUN_INSTALL "$HOME/.bun"
      fish_add_path $BUN_INSTALL/bin
      
      # GCloud SDK
      if test -d /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin
        fish_add_path /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin
      end
      
      # Legacy GCloud SDK location
      if test -f '/Users/alex/Downloads/google-cloud-sdk/path.fish.inc'
        source '/Users/alex/Downloads/google-cloud-sdk/path.fish.inc'
      end
      
      # Rancher Desktop
      fish_add_path --prepend "/Users/alex/.rd/bin"
      
      # KUBECONFIG
      set -gx KUBECONFIG "$HOME/.kube/config:$HOME/.docctor/config/kubeconfig"
      
      # Terragrunt cache
      set -gx TG_PROVIDER_CACHE 1
    '';
    
    interactiveShellInit = ''
      # Autojump integration
      test -f ${pkgs.autojump}/share/autojump/autojump.fish; and source ${pkgs.autojump}/share/autojump/autojump.fish
    '';
    
    functions = {
      # macOS-specific SSH agent key management
      sshagent_add_key_macos = {
        description = "Add SSH key to macOS keychain";
        body = "ssh-add --apple-use-keychain $argv";
      };
      
      sshagent_add_key = {
        description = "Add SSH key";
        body = "ssh-add $argv";
      };
      
      sshagent_add_keys = {
        description = "Add all SSH keys from bitwarden";
        body = ''
          set files "$HOME/.ssh/bitwarden"
          for f in $files
            if not ssh-add -L | grep -q $f
              if uname -a | grep -q Darwin
                sshagent_add_key_macos $f
              else
                sshagent_add_key $f
              end
            end
          end
        '';
      };
      
      # Ghostty SSH with terminfo
      gssh = {
        description = "copies ghostty terminfo onto ssh targets";
        body = ''
          infocmp -x xterm-ghostty | ssh $argv[1] tic -x -
          ssh $argv
        '';
      };
      
      # macOS-specific rmterra override (uses find instead of fd)
      rmterra = {
        description = "recursively find and delete .terragrunt-cache dirs";
        body = "find . -type d -name '.terragrunt-cache' -exec rm -rf {} +";
      };
    };
  };

  # Tmux configuration
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    keyMode = "vi";
    customPaneNavigationAndResize = true;
    escapeTime = 0;
    historyLimit = 50000;
    plugins = [
      {
        plugin = pkgs.tmuxPlugins.mkTmuxPlugin {
          pluginName = "tmux-pane-focus";
          rtpFileTmux = "focus.tmux";
          version = "unstable-2025-10-07";
          src = pkgs.fetchFromGitHub {
            owner = "graemedavidson";
            repo = "tmux-pane-focus";
            rev = "525ce8117220de82331a97fec87fa6b54bad81df";
            sha256 = "sha256-dkXTWZcNfs1+BelKuRzN268jF1CwIIObz9VJDLwMHvE=";
          };
        };
        extraConfig = ''
          set -g @pane-focus-size '80'
          set -g @pane-focus-direction '-'
        '';
      }
    ];
  };
}
