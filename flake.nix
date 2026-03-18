{
    description = "Alex's Nix systems";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

        nix-darwin.url = "github:nix-darwin/nix-darwin/master";
        nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

        home-manager.url = "github:nix-community/home-manager";
        home-manager.inputs.nixpkgs.follows = "nixpkgs";

        nixvim.url = "github:nix-community/nixvim";
        # The docs say that using .follows here can cause instability in
        # nixvim and so it is not used.

        dgop = {
          url = "github:AvengeMedia/dgop";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        opencode = {
          url = "github:anomalyco/opencode";
        };

        nix-software-center = {
          url = "github:snowfallorg/nix-software-center";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        # Provides bleeding edge claude-code updates
        claude-code.url = "github:sadjow/claude-code-nix";

        # nix-openclaw — kept for steipete-tools skill binaries
        nix-openclaw = {
          url = "github:openclaw/nix-openclaw";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        # openclaw plugins
        xuezh = {
          url = "github:joshp123/xuezh";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        # GoClaw source (no flake.nix — built locally via buildGoModule)
        goclaw-src = {
          url = "github:nextlevelbuilder/goclaw";
          flake = false;
        };

        # koch (NAS) dependencies
        disko = {
          url = "github:nix-community/disko";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        sops-nix = {
          url = "github:Mic92/sops-nix";
          inputs.nixpkgs.follows = "nixpkgs";
        };

    };

    outputs = {self, nixpkgs, nix-darwin, home-manager, nixvim, claude-code, opencode, nix-openclaw, xuezh, goclaw-src, nix-software-center, disko, sops-nix, ...}@inputs:
    let
        # Shared goclaw overlay — used by koch, darwin, and devShells
        goclawOverlay = (final: prev: {
          goclaw = final.callPackage ./nix/pkgs/goclaw.nix {
            inherit goclaw-src;
          };
          goclaw-ui = final.callPackage ./nix/pkgs/goclaw-ui.nix {
            inherit goclaw-src;
          };
          grocy-mcp = final.callPackage ./nix/pkgs/grocy-mcp.nix {};
        });

        kochOverlay = (final: prev: {
          claude-code = inputs.claude-code.packages.${final.system}.default;
        } // (goclawOverlay final prev));

        mkPkgs = system: overlays: import nixpkgs {
          inherit system overlays;
        };

        # Per-host goclaw devShell factory
        mkGoclawShell = { system, hostName, stateDir, port, secretsFile, sopsKeyFile, serviceUser }:
          let
            pkgs = mkPkgs system [ goclawOverlay claude-code.overlays.default ];
            goclawAdmin = pkgs.writeShellScriptBin "goclaw-admin" ''
              set -euo pipefail
              exec sudo -u ${serviceUser} env GOCLAW_BIN="${pkgs.goclaw}/bin/goclaw" bash -lc '
                set -euo pipefail
                if [ -f "${stateDir}/.env" ]; then
                  set -a; source "${stateDir}/.env"; set +a
                elif [ -f "/run/goclaw/env" ]; then
                  set -a; source /run/goclaw/env; set +a
                fi
                export GOCLAW_CONFIG=${stateDir}/config/goclaw.json
                export GOCLAW_HOST=127.0.0.1
                export GOCLAW_PORT=${toString port}
                exec "$GOCLAW_BIN" "$@"
              ' _ "$@"
            '';
            sopsEdit = pkgs.writeShellScriptBin "sops-${hostName}" ''
              set -euo pipefail
              repo_root="''${GOCLAW_DOTFILES_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
              default_file="$repo_root/${secretsFile}"
              export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-${sopsKeyFile}}"
              if [ "$#" -eq 0 ]; then set -- "$default_file"; fi
              exec ${pkgs.sops}/bin/sops "$@"
            '';
            claudeGoclaw = pkgs.writeShellScriptBin "claude-goclaw" ''
              set -euo pipefail
              exec sudo -u ${serviceUser} env CLAUDE_BIN="${pkgs.claude-code}/bin/claude" bash -lc '
                set -euo pipefail
                if [ -f "${stateDir}/.env" ]; then
                  set -a; source "${stateDir}/.env"; set +a
                elif [ -f "/run/goclaw/env" ]; then
                  set -a; source /run/goclaw/env; set +a
                fi
                export HOME=${stateDir}
                export GOCLAW_CONFIG=${stateDir}/config/goclaw.json
                export GOCLAW_HOST=127.0.0.1
                export GOCLAW_PORT=${toString port}
                exec "$CLAUDE_BIN" "$@"
              ' _ "$@"
            '';
          in
          pkgs.mkShell {
            packages = with pkgs; [
              goclaw
              claude-code
              jq yq curl age sops
              goclawAdmin sopsEdit claudeGoclaw
            ];
            shellHook = ''
              export GOCLAW_CONFIG=${stateDir}/config/goclaw.json
              export GOCLAW_HOST=127.0.0.1
              export GOCLAW_PORT=${toString port}

              echo "${hostName} goclaw shell ready"
              echo "- Run goclaw as service user:  goclaw-admin pairing list"
              echo "- Approve a code:              goclaw-admin pairing approve ABCD12"
              echo "- Run Claude as goclaw user:   claude-goclaw"
              echo "- Edit ${hostName} secrets:         sops-${hostName}"
            '';
          };

    in {
        nixosConfigurations = {
            mandelbrot = nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                specialArgs = { inherit inputs; };
                modules = [
                    ./nix/modules/tailscale-serve.nix
                    ./nix/mandelbrot/configuration.nix
                    ./nix/mandelbrot/hardware.nix
                    home-manager.nixosModules.home-manager
                    {
                        home-manager.useGlobalPkgs = true;
                        home-manager.useUserPackages = true;
                        home-manager.extraSpecialArgs = { inherit inputs; };
                        home-manager.users.alex = ./nix/mandelbrot/alex.nix;
                        home-manager.backupFileExtension = ".before";
                        nixpkgs.overlays = [ opencode.overlays.default ];
                    }
                ];
            };
            julia = nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                specialArgs = { inherit inputs; };
                modules = [
                    ./nix/julia/configuration.nix
                    ./nix/julia/hardware.nix
                    home-manager.nixosModules.home-manager
                    {
                        home-manager.useGlobalPkgs = true;
                        home-manager.useUserPackages = true;
                        home-manager.extraSpecialArgs = { inherit inputs; };
                        home-manager.users.alex = ./nix/julia/alex.nix;
                        home-manager.users.cass = ./nix/julia/cass.nix;
                        home-manager.backupFileExtension = ".before";
                        nixpkgs.overlays = [ opencode.overlays.default ];
                    }
                ];
            };
            koch = nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                specialArgs = { inherit inputs; };
                modules = [
                    {
                      nixpkgs.overlays = [ kochOverlay ];
                    }
                    disko.nixosModules.disko
                    sops-nix.nixosModules.sops
                    ./nix/modules/tailscale-serve.nix
                    ./nix/koch/configuration.nix
                    ./nix/koch/hardware.nix
                    ./nix/koch/disk-config.nix
                    home-manager.nixosModules.home-manager
                    {
                        home-manager.useGlobalPkgs = true;
                        home-manager.useUserPackages = true;
                        home-manager.extraSpecialArgs = { inherit inputs; };
                        home-manager.users.alex = ./nix/koch/alex.nix;
                        home-manager.backupFileExtension = ".before";
                    }
                ];
            };
        };
        devShells.x86_64-linux.koch-goclaw = mkGoclawShell {
          system = "x86_64-linux";
          hostName = "koch";
          stateDir = "/data/state-store/goclaw";
          port = 18789;
          secretsFile = "nix/koch/secrets.yaml";
          sopsKeyFile = "/var/lib/sops-nix/keys.txt";
          serviceUser = "goclaw";
        };

        devShells.aarch64-darwin.mac-goclaw = mkGoclawShell {
          system = "aarch64-darwin";
          hostName = "mac";
          stateDir = "/var/lib/goclaw";
          port = 18790;
          secretsFile = "nix/Alexs-Macbook-Pro/secrets.yaml";
          sopsKeyFile = "/Users/alex/Library/Application Support/sops/age/keys.txt";
          serviceUser = "_goclaw";
        };
        darwinConfigurations = {
            "Alexs-MacBook-Pro" = nix-darwin.lib.darwinSystem {
               system = "aarch64-darwin";
               specialArgs = { inherit inputs; };
               modules = [
                    sops-nix.darwinModules.sops
                    ./nix/Alexs-Macbook-Pro/configuration.nix
                    ./nix/Alexs-Macbook-Pro/hardware.nix
                    home-manager.darwinModules.home-manager
                    {
                        nixpkgs.overlays = [
                          claude-code.overlays.default
                          goclawOverlay
                        ];
                        home-manager.useGlobalPkgs = true;
                        home-manager.useUserPackages = true;
                        home-manager.backupFileExtension = "backup";
                        home-manager.extraSpecialArgs = { inherit inputs; };
                        home-manager.users.alex = ./nix/Alexs-Macbook-Pro/alex.nix;
                    }
               ];
            };
        };
    };
}
