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

        dankMaterialShell = {
          url = "github:AvengeMedia/DankMaterialShell";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        opencode = {
          url = "github:anomalyco/opencode";
        };

        # Provides bleeding edge claude-code updates
        claude-code.url = "github:sadjow/claude-code-nix";
    };

    outputs = {self, nixpkgs, nix-darwin, home-manager, nixvim, claude-code, opencode, ...}@inputs: {
        nixosConfigurations = {
            mandelbrot = nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                specialArgs = { inherit inputs; };
                modules = [
                    ./nix/mandelbrot/configuration.nix
                    ./nix/mandelbrot/hardware.nix
                    home-manager.nixosModules.home-manager
                    {
                        home-manager.useGlobalPkgs = true;
                        home-manager.useUserPackages = true;
                        home-manager.extraSpecialArgs = { inherit inputs; };
                        home-manager.users.alex = ./nix/mandelbrot/alex.nix;
                        home-manager.backupFileExtension = ".before";
                        nixpkgs.overlays = [
                            opencode.overlays.default
                            # TODO: remove once fish 4.5.0 lands in nixos-unstable
                            (final: prev: {
                              fish = prev.fish.overrideAttrs (old: rec {
                                version = "4.5.0";
                                src = prev.fetchFromGitHub {
                                  owner = "fish-shell";
                                  repo = "fish-shell";
                                  tag = version;
                                  hash = "sha256-9EhvCStAeL+ADkLy9b4gXPx+JrVzUZ5Fdkf+imY3Vw0=";
                                };
                                cargoDeps = prev.rustPlatform.fetchCargoVendor {
                                  inherit src;
                                  inherit (old) patches;
                                  hash = "sha256-RVg6Zciy9mqZQwM5P3ngJi2NjC0qwFH7XgVEanaKnsg=";
                                };
                              });
                            })
                        ];
                    }
                ];
            };
        };
        darwinConfigurations = {
            "Alexs-MacBook-Pro" = nix-darwin.lib.darwinSystem {
               system = "aarch64-darwin";
               specialArgs = { inherit inputs; };
               modules = [
                    ./nix/Alexs-Macbook-Pro/configuration.nix
                    ./nix/Alexs-Macbook-Pro/hardware.nix
                    home-manager.darwinModules.home-manager
                    {
                        # This makes it so that wherever I use packages.claude-code it will use sadjow/claude-code-nix
                        nixpkgs.overlays = [ claude-code.overlays.default ];
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
