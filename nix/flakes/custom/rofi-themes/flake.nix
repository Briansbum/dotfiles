{
  description = "adi1090x rofi themes and fonts as a nix package";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "rofi-themes-adi1090x";
          version = "unstable";

          src = pkgs.fetchFromGitHub {
            owner = "adi1090x";
            repo = "rofi";
            rev = "master";
            sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            # Run once with incorrect hash to get the correct one
          };

          nativeBuildInputs = [ pkgs.fontconfig ];

          buildPhase = "true"; # no build necessary

          installPhase = ''
            mkdir -p $out/share/fonts
            mkdir -p $out/share/rofi

            cp -r fonts/* $out/share/fonts/
            cp -r files/* $out/share/rofi/
          '';

          meta = with pkgs.lib; {
            description = "Themes, fonts and configs for rofi by adi1090x";
            homepage = "https://github.com/adi1090x/rofi";
            license = licenses.gpl3Plus;
            platforms = platforms.pc;
          };
        };
      });
}
