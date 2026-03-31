{ lib, buildNpmPackage, nodejs_22, python3, pkg-config, sqlite, recipe-import-src }:

buildNpmPackage {
  pname   = "recipe-import";
  version = "0.1.0";

  src = recipe-import-src;

  # Run `nix build .#recipe-import` — the error message contains the correct hash.
  npmDepsHash = lib.fakeHash;

  nodejs = nodejs_22;

  nativeBuildInputs = [ python3 pkg-config nodejs_22 ];
  buildInputs       = [ sqlite ];

  buildPhase = ''
    runHook preBuild
    # .npmrc enforces ignore-scripts for npm install.
    # Override here to explicitly compile the native addon we've reviewed.
    npm rebuild better-sqlite3 --ignore-scripts=false --build-from-source
    npm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r .next/standalone/. $out/
    mkdir -p $out/.next
    cp -r .next/static $out/.next/static
    cp -r public $out/public 2>/dev/null || true
    runHook postInstall
  '';

  meta.description = "Recipe import tool for Grocy";
}
