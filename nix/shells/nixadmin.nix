# Development shell for administering NixOS/nix-darwin machines.
#
# A sops-<host> script is generated for every host that has a
# secrets.yaml at nix/<host>/secrets.yaml.
#
# Usage in flake.nix:
#   devShells.aarch64-darwin.nixadmin = import ./nix/shells/nixadmin.nix {
#     inherit nixpkgs;
#     system = "aarch64-darwin";
#   };

{ nixpkgs, system }:

let
  pkgs = import nixpkgs { inherit system; };

  sopsKeyFile =
    if system == "aarch64-darwin"
    then "/Users/alex/Library/Application Support/sops/age/keys.txt"
    else "/var/lib/sops-nix/keys.txt";

  nixDir = ../nix;

  hostsWithSecrets = builtins.attrNames (builtins.filterAttrs
    (name: type: type == "directory" && builtins.pathExists "${nixDir}/${name}/secrets.yaml")
    (builtins.readDir nixDir));

  mkSopsEdit = hostName:
    pkgs.writeShellScriptBin "sops-${hostName}" ''
      set -euo pipefail
      repo_root="''${DOTFILES_ROOT:-$(git rev-parse --show-toplevel)}"
      export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-${sopsKeyFile}}"
      target="$repo_root/nix/${hostName}/secrets.yaml"
      if [ "$#" -eq 0 ]; then set -- "$target"; fi
      exec ${pkgs.sops}/bin/sops "$@"
    '';

  sopsScripts = map mkSopsEdit hostsWithSecrets;

in
pkgs.mkShell {
  packages = with pkgs; [
    sops age ssh-to-age
    jq yq
  ] ++ sopsScripts;

  shellHook = ''
    export SOPS_AGE_KEY_FILE="${sopsKeyFile}"

    echo "NixOS admin shell ready"
    echo ""
    echo "Secrets (sops-<host> for each host with nix/<host>/secrets.yaml):"
    ${pkgs.lib.concatMapStrings (h: "echo \"  sops-${h}\"\n") hostsWithSecrets}
    echo ""
    echo "Deploy (run from repo root):"
    echo "  nixos-rebuild switch --flake .#<host> --target-host root@<host> --use-remote-sudo"
  '';
}
