{ lib, buildGoModule, grocy-mobile-src }:

buildGoModule {
  pname = "grocy-mobile";
  version = "0.1.0";

  src = grocy-mobile-src;

  vendorHash = null; # no external deps

  env.CGO_ENABLED = 0;

  ldflags = [ "-s" "-w" ];

  meta = with lib; {
    description = "Mobile-first web frontend for Grocy tasks and chores";
    mainProgram = "grocy-mobile";
  };
}
