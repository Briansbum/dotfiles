# Recipe Import on koch — Traefik-fronted, Grocy integration.
#
# Pre-deploy checklist:
#   1. Add recipe_import_grocy_api_key to nix/koch/secrets.yaml via sops
#   2. Set npmDepsHash in pkgs/recipe-import.nix (run `nix build .#recipe-import` to get it)
#   3. Seed claude auth in the data dir so the container can invoke `claude -p`:
#        sudo -u recipe-import env HOME=/data/recipe-import claude
#      Then accept the auth prompt once; credentials persist in /data/recipe-import/.claude/

{ config, pkgs, ... }:

{
  imports = [ ../modules/recipe-import/nixos.nix ];

  services.recipe-import = {
    enable       = true;
    uid          = 986;
    gid          = 986;
    port         = 3100;
    dataDir      = "/data/recipe-import";
    package      = pkgs.recipe-import;
    # Grocy on host, reached via host.docker.internal from the container
    grocyBaseUrl = "http://host.docker.internal:2383";
  };

  # Traefik router
  services.traefik.dynamicConfigOptions.http.routers.recipe-import = {
    rule            = "Host(`recipes.koch.brians.skin`)";
    service         = "recipe-import";
    tls.certResolver = "desec";
  };
  services.traefik.dynamicConfigOptions.http.services.recipe-import.loadBalancer.servers = [
    { url = "http://localhost:${toString config.services.recipe-import.port}"; }
  ];
}
