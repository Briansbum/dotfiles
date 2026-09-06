# knot vm - hosts tangled git repos

{
  inputs,
}:
import ./mk-service-vm.nix {
  inherit inputs;
  name = "knot";
  modules = [
    (
      { lib, ... }:
      {
        imports = [ inputs.chorcy.nixosModules.default ];
        services.chorcy.enable = true;

        koch-vm = {
          memory = 256;
          ports = [
            { guestPort = 2483; } # -> 127.0.0.1:2483, Traefik fronts this
          ];
        };
      }
    )
  ];
}
