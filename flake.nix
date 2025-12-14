{
    description = "Baby's first nixos flake";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

        home-manager.url = "github:nix-community/home-manager";
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

    outputs = {self, nixpkgs, ...}@inputs: {
        nixosConfigurations = {
            mandelbrot = nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                specialArgs = { inherit inputs; };
                modules = [
                    ./nix/flakes/configuration.nix
                    ./nix/flakes/hardware/mandelbrot.nix
                ];
            };
        };
    };
}
