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

        nix-software-center = {
          url = "github:snowfallorg/nix-software-center";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        # Provides bleeding edge claude-code updates
        claude-code.url = "github:sadjow/claude-code-nix";

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

    outputs = {self, nixpkgs, nix-darwin, home-manager, nixvim, claude-code, nix-software-center, disko, sops-nix, ...}@inputs:
    let
        kochOverlay = (final: prev: {
          claude-code    = inputs.claude-code.packages.${final.stdenv.hostPlatform.system}.default;
        });

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

        darwinConfigurations = {
            "Alexs-MacBook-Pro" = nix-darwin.lib.darwinSystem {
               system = "aarch64-darwin";
               specialArgs = { inherit inputs; };
               modules = [
                    ./nix/Alexs-Macbook-Pro/configuration.nix
                    ./nix/Alexs-Macbook-Pro/hardware.nix
                    home-manager.darwinModules.home-manager
                    {
                        nixpkgs.overlays = [
                          claude-code.overlays.default
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

        devShells.aarch64-darwin.nixadmin = import ./nix/shells/nixadmin.nix {
          inherit nixpkgs;
          system = "aarch64-darwin";
        };
    };
}
