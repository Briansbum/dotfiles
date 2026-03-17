{ lib, buildGoModule }:

buildGoModule {
  pname = "grocy-mcp";
  version = "0.1.0";

  src = ../koch/scripts/grocy-mcp;

  vendorHash = null; # no external deps

  env.CGO_ENABLED = 0;

  ldflags = [ "-s" "-w" ];

  meta = with lib; {
    description = "MCP server exposing the Grocy household management API";
    mainProgram = "grocy-mcp";
  };
}
