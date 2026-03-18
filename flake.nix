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

        mkGoclawShell = import ./nix/shells/goclaw.nix {
          inherit nixpkgs;
          overlays = [ goclawOverlay claude-code.overlays.default ];
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
          postgresDSN = "postgres://goclaw@/goclaw?host=/run/postgresql";
          secretsFile = "nix/koch/secrets.yaml";
          sopsKeyFile = "/var/lib/sops-nix/keys.txt";
          serviceUser = "goclaw";
        };

        devShells.aarch64-darwin.mac-goclaw = mkGoclawShell {
          system = "aarch64-darwin";
          hostName = "mac";
          stateDir = "/var/lib/goclaw";
          port = 18790;
          postgresDSN = "postgres://goclaw@localhost:5432/goclaw?sslmode=disable";
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
