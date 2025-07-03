{
  description = "Greetd with Sway + GtkGreet and ricing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        backgroundImage = ./images/omnium.png;

        gtkgreetCss = pkgs.writeText "gtkgreet.css" ''
          window {
            background-image: url("${backgroundImage}");
            background-size: cover;
            background-position: center;
          }

          #window {
            background-color: rgba(10, 10, 10, 0.9);
            padding: 20px;
          }

          #body {
            background-color: transparent;
            color: rgba(216, 222, 233, 0.80);
            font-family: "Go Mono", monospace;
          }

          #clock {
            color: rgba(10, 10, 10, 0.75);
            font-size: 40px;
          }

          #input, #inputbox {
            background-color: rgba(10, 10, 10, 0.9);
            color: rgb(200, 200, 200);
            font-family: "Go Mono", monospace;
            border: none;
            padding: 15px;
            margin: 5px;
            min-width: 320px;
            min-height: 55px;
          }

          button {
            background-color: rgba(10, 10, 10, 0.9);
            color: rgba(216, 222, 233, 0.80);
            padding: 15px 30px;
            margin: 5px;
            font-family: "Go Mono", monospace;
            border: none;
          }

          button:hover {
            background-color: rgba(30, 30, 30, 0.9);
          }

          label {
            color: rgba(10, 10, 10, 0.75);
            font-family: "Go Mono", monospace;
          }
        '';

        swayGreetConfig = pkgs.writeText "greetd-sway-config" ''
          output DP-2 resolution 2560x1440 position 0,0
          output DP-4 resolution 3840x2160 position 2561,0 transform 270
          output * bg ${backgroundImage} fill
          default_border none

          exec "${pkgs.greetd.gtkgreet}/bin/gtkgreet -l -s ${gtkgreetCss}; swaymsg exit"
          for_window [app_id=".*"] inhibit_idle fullscreen
        '';

      in {
        nixosConfigurations.default = pkgs.lib.nixosSystem {
          system = system;
          modules = [
            ({ config, ... }: {
              imports = [ ];

              services.displayManager.sddm.enable = false;

              services.greetd = {
                enable = true;
                settings.default_session = {
                  command = "${pkgs.sway}/bin/sway -c ${swayGreetConfig}";
                  user = "greeter";
                };
              };

              users.users.greeter = {
                isSystemUser = true;
                group = "greeter";
                home = "/var/lib/greeter";
                createHome = true;
                extraGroups = [ "video" "input" ];
              };

              users.groups.greeter = {};

              fonts.packages = with pkgs; [
                nerd-fonts.go-mono
              ];

              environment.etc."greetd/environments".text = ''
                Hyprland
              '';

              environment.systemPackages = with pkgs; [
                sway
                greetd.greetd
                greetd.gtkgreet
              ];

              security.pam.services.greetd.enableGnomeKeyring = true;
            })
          ];
        };
      });
}
