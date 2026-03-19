{ lib, stdenv, pnpmConfigHook, fetchPnpmDeps, pnpm, nodejs, goclaw-src }:

stdenv.mkDerivation (finalAttrs: {
  pname = "goclaw-ui";
  version = "0.1.0";

  src = "${goclaw-src}/ui/web";

  nativeBuildInputs = [ pnpmConfigHook pnpm nodejs ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-f6HQ0Q4z/PxrPYNHQ8Yktzeq5WwMt7fqL5hW7s2zdnc=";
    fetcherVersion = 1;
  };

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/goclaw-ui
    cp -r dist/* $out/share/goclaw-ui/
    runHook postInstall
  '';

  meta = with lib; {
    description = "GoClaw web dashboard";
    homepage = "https://github.com/nextlevelbuilder/goclaw";
  };
})
