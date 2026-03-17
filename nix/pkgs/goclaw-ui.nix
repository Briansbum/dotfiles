{ lib, stdenv, pnpmConfigHook, fetchPnpmDeps, nodejs, goclaw-src }:

stdenv.mkDerivation (finalAttrs: {
  pname = "goclaw-ui";
  version = "0.1.0";

  src = "${goclaw-src}/ui/web";

  nativeBuildInputs = [ pnpmConfigHook nodejs ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-v+02RvDMz5Shcgu1ZehbownHxx66s+h8qfC3CbH2Rpo=";
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
