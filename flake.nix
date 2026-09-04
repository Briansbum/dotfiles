{
  description = "Alex's Nix systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";

    nix-software-center = {
      url = "github:snowfallorg/nix-software-center";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Provides bleeding edge claude-code updates
    claude-code.url = "github:sadjow/claude-code-nix";
    claude-code.inputs.nixpkgs.follows = "nixpkgs";

    # koch (NAS) dependencies
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zmx.url = "github:Briansbum/zmx/session-restore";

    # Doccla CLI, macbook only
    docctor = {
      url = "git+ssh://git@github.com/doccla-experiments/docctor.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Chore chart PWA for Grocy — flake ships a static bundle + NixOS module
    chorcy = {
      url = "git+ssh://git@codeberg.org/briansbum/chorcy.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      nixvim,
      claude-code,
      nix-software-center,
      disko,
      sops-nix,
      chorcy,
      ...
    }@inputs:
    let
      kochOverlay = (
        final: prev: {
          claude-code = inputs.claude-code.packages.${final.stdenv.hostPlatform.system}.default;
        }
      );

      zmxOverlay = (
        final: prev: {
          zmx = inputs.zmx.packages.${final.stdenv.hostPlatform.system}.zmx;
        }
      );

      # Built from the docctor source rather than its own flake output, which
      # sets vendorHash = null against a repo that ships no vendor dir.
      docctorOverlay = (
        final: prev: {
          docctor = final.buildGoModule rec {
            pname = "docctor";
            version = inputs.docctor.shortRev or "dev";
            src = "${inputs.docctor}/cli";
            vendorHash = "sha256-EqkQwW6w3/u/5ccOQjK9jIAS+6mRLxm2To4T6cs4QUI=";
            subPackages = [ "cmd" ];
            ldflags = [
              "-X main.version=${version}"
              "-X main.commit=${inputs.docctor.rev or "dirty"}"
              "-X main.branch=nix-build"
            ];
            postInstall = "mv $out/bin/cmd $out/bin/docctor";
            meta.mainProgram = "docctor";
          };
        }
      );

    in
    {
      nixosConfigurations = {
        mandelbrot = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            { nixpkgs.overlays = [ zmxOverlay ]; }
            ./nix/modules/tailscale-serve.nix
            ./nix/mandelbrot/configuration.nix
            ./nix/mandelbrot/hardware.nix
            sops-nix.nixosModules.sops
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
            { nixpkgs.overlays = [ zmxOverlay ]; }
            ./nix/julia/configuration.nix
            ./nix/julia/hardware.nix
            sops-nix.nixosModules.sops
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
        # Per-service micro VMs run as rootless QEMU/KVM units on koch.
        koch-chorcy = import ./nix/koch/vms/chorcy.nix { inherit inputs; };
        koch-grocy = import ./nix/koch/vms/grocy.nix { inherit inputs; };
        koch-immich = import ./nix/koch/vms/immich.nix { inherit inputs; };
        koch-syncthing = import ./nix/koch/vms/syncthing.nix { inherit inputs; };
        koch-git = import ./nix/koch/vms/git.nix { inherit inputs; };

        koch = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            {
              nixpkgs.overlays = [
                kochOverlay
                zmxOverlay
              ];
            }
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            chorcy.nixosModules.default
            ./nix/koch/vms/runner.nix
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
        sierpinski = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            disko.nixosModules.disko
            ./nix/sierpinski/configuration.nix
            ./nix/sierpinski/hardware.nix
            ./nix/sierpinski/disk-config.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };
              home-manager.users.alex = ./nix/sierpinski/alex.nix;
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
                zmxOverlay
                docctorOverlay
                # direnv's zsh test hangs on macOS 26 (waitforpid/SIGCHLD)
                (final: prev: {
                  direnv = prev.direnv.overrideAttrs (old: {
                    checkPhase = ''
                      runHook preCheck
                      make test-go test-bash test-fish
                      runHook postCheck
                    '';
                  });
                })
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
        nixosHosts = builtins.attrNames self.nixosConfigurations;
      };
      devShells.x86_64-linux.nixadmin = import ./nix/shells/nixadmin.nix {
        inherit nixpkgs;
        system = "x86_64-linux";
        nixosHosts = builtins.attrNames self.nixosConfigurations;
      };
    };
}
