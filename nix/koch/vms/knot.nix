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

        koch-vm = {
          memory = 256;
        };
      }
    )
  ];
}
