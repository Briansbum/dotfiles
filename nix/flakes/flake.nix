{
    description = "Baby's first nixos flake";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
        home-manager.url = "github:nix-community/home-manager";
    };

    outputs = {self, nixpkgs, ...}@inputs: {
        nixosConfigurations = {
            nixos = nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                specialArgs = { inherit inputs; };
                modules = [
                    ./configuration.nix
                    ./hardware/mandelbrot.nix
                ];
            };
        };
    };
}
