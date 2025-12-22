{
    description = "Baby's first nixos flake";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

        home-manager.url = "github:nix-community/home-manager";
        home-manager.inputs.nixpkgs.follows = "nixpkgs";

        hyprland.url = "github:hyprwm/Hyprland";

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

    outputs = {self, nixpkgs, home-manager, ...}@inputs: {
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
    };
}
