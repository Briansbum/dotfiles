# Development shell for administering NixOS/nix-darwin machines.
#
# A sops-<host> script is generated for every host that has a
# secrets.yaml at nix/<host>/secrets.yaml.
#
# A deploy-<host> script is generated for every nixosConfiguration, on
# x86_64-linux only. The closure is built on the invoking machine and pushed to
# the target, so the origin must already be x86_64-linux — there is no remote
# building here. Override the SSH destination with TARGET_HOST.
#
# Usage in flake.nix:
#   devShells.aarch64-darwin.nixadmin = import ./nix/shells/nixadmin.nix {
#     inherit nixpkgs;
#     system = "aarch64-darwin";
#     nixosHosts = builtins.attrNames self.nixosConfigurations;
#   };

{
  nixpkgs,
  system,
  nixosHosts,
}:

let
  pkgs = import nixpkgs { inherit system; };

  isLinux = system == "x86_64-linux";

  sopsKeyFile =
    if system == "aarch64-darwin" then
      "/Users/alex/Library/Application Support/sops/age/keys.txt"
    else
      "/var/lib/sops-nix/keys.txt";

  nixDir = ../.;

  hostsWithSecrets = builtins.attrNames (
    pkgs.lib.filterAttrs (
      name: type: type == "directory" && builtins.pathExists (nixDir + "/${name}/secrets.yaml")
    ) (builtins.readDir nixDir)
  );

  mkSopsEdit =
    hostName:
    pkgs.writeShellScriptBin "sops-${hostName}" ''
      set -euo pipefail
      repo_root="''${DOTFILES_ROOT:-$(git rev-parse --show-toplevel)}"
      export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-${sopsKeyFile}}"
      target="$repo_root/nix/${hostName}/secrets.yaml"
      if [ "$#" -eq 0 ]; then set -- "$target"; fi
      exec ${pkgs.sops}/bin/sops "$@"
    '';

  sopsScripts = map mkSopsEdit hostsWithSecrets;

  mkDeploy =
    hostName:
    pkgs.writeShellScriptBin "deploy-${hostName}" ''
      set -euo pipefail
      repo_root="''${DOTFILES_ROOT:-$(git rev-parse --show-toplevel)}"
      target="''${TARGET_HOST:-alex@${hostName}}"
      cd "$repo_root"
      exec nixos-rebuild switch \
        --flake ".#${hostName}" \
        --target-host "$target" \
        --sudo \
        --no-reexec \
        "$@"
    '';

  deployScripts = if isLinux then map mkDeploy nixosHosts else [ ];

in
pkgs.mkShell {
  packages =
    with pkgs;
    [
      sops
      age
      ssh-to-age
      jq
      yq
    ]
    ++ pkgs.lib.optional isLinux pkgs.nixos-anywhere
    ++ sopsScripts
    ++ deployScripts;

  shellHook = ''
    export SOPS_AGE_KEY_FILE="${sopsKeyFile}"

    echo "NixOS admin shell ready"
    echo ""
    echo "Secrets (sops-<host> for each host with nix/<host>/secrets.yaml):"
    ${pkgs.lib.concatMapStrings (h: "echo \"  sops-${h}\"\n") hostsWithSecrets}
    echo ""
    ${
      if isLinux then
        ''
          echo "Deploy (builds here, pushes to the target):"
          ${pkgs.lib.concatMapStrings (h: "echo \"  deploy-${h}\"\n") nixosHosts}
          echo ""
          echo "  TARGET_HOST=alex@1.2.3.4 deploy-<host>   override the SSH destination"
          echo "  nixos-anywhere --flake .#<host> root@<ip>   first install"
        ''
      else
        ''
          echo "Deploy: run from an x86_64-linux fleet host (koch, mandelbrot, julia)."
          echo "This machine cannot build x86_64-linux closures."
        ''
    }
  '';
}
