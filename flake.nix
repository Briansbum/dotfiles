{
    description = "Alex's Nix systems";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

        nix-darwin.url = "github:nix-darwin/nix-darwin/master";
        nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

        home-manager.url = "github:nix-community/home-manager";
        home-manager.inputs.nixpkgs.follows = "nixpkgs";

        dgop = {
          url = "github:AvengeMedia/dgop";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        dankMaterialShell = {
          url = "github:AvengeMedia/DankMaterialShell";
          inputs.nixpkgs.follows = "nixpkgs";
          inputs.dgop.follows = "dgop";
        };
    };

    outputs = {self, nixpkgs, nix-darwin, home-manager, ...}@inputs: {
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
                        home-manager.users.alex = ./nix/mandelbrot/alex.nix;
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
                        home-manager.useGlobalPkgs = true;
                        home-manager.useUserPackages = true;
                        home-manager.backupFileExtension = "backup";
                        home-manager.users.alex = ./nix/Alexs-Macbook-Pro/alex.nix;
                    }
               ];
            };
        };
    };
}
