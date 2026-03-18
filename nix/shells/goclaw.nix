# Per-host goclaw devShell factory.
#
# Usage in flake.nix:
#   mkGoclawShell = import ./nix/shells/goclaw.nix { inherit nixpkgs; overlays = [ ... ]; };
#   devShells.x86_64-linux.koch-goclaw = mkGoclawShell { system = "x86_64-linux"; ... };

{ nixpkgs, overlays }:

{ system, hostName, stateDir, port, secretsFile, sopsKeyFile, serviceUser }:

let
  pkgs = import nixpkgs { inherit system overlays; };

  goclawAdmin = pkgs.writeShellScriptBin "goclaw-admin" ''
    set -euo pipefail
    exec sudo -u ${serviceUser} env GOCLAW_BIN="${pkgs.goclaw}/bin/goclaw" bash -lc '
      set -euo pipefail
      if [ -f "${stateDir}/.env" ]; then
        set -a; source "${stateDir}/.env"; set +a
      elif [ -f "/run/goclaw/env" ]; then
        set -a; source /run/goclaw/env; set +a
      fi
      export GOCLAW_CONFIG=${stateDir}/config/goclaw.json
      export GOCLAW_HOST=127.0.0.1
      export GOCLAW_PORT=${toString port}
      exec "$GOCLAW_BIN" "$@"
    ' _ "$@"
  '';

  sopsEdit = pkgs.writeShellScriptBin "sops-${hostName}" ''
    set -euo pipefail
    repo_root="''${GOCLAW_DOTFILES_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    default_file="$repo_root/${secretsFile}"
    export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-${sopsKeyFile}}"
    if [ "$#" -eq 0 ]; then set -- "$default_file"; fi
    exec ${pkgs.sops}/bin/sops "$@"
  '';

  claudeGoclaw = pkgs.writeShellScriptBin "claude-goclaw" ''
    set -euo pipefail
    exec sudo -u ${serviceUser} env CLAUDE_BIN="${pkgs.claude-code}/bin/claude" bash -lc '
      set -euo pipefail
      if [ -f "${stateDir}/.env" ]; then
        set -a; source "${stateDir}/.env"; set +a
      elif [ -f "/run/goclaw/env" ]; then
        set -a; source /run/goclaw/env; set +a
      fi
      export HOME=${stateDir}
      export GOCLAW_CONFIG=${stateDir}/config/goclaw.json
      export GOCLAW_HOST=127.0.0.1
      export GOCLAW_PORT=${toString port}
      exec "$CLAUDE_BIN" "$@"
    ' _ "$@"
  '';
in
pkgs.mkShell {
  packages = with pkgs; [
    goclaw
    claude-code
    jq yq curl age sops
    goclawAdmin sopsEdit claudeGoclaw
  ];

  shellHook = ''
    export GOCLAW_CONFIG=${stateDir}/config/goclaw.json
    export GOCLAW_HOST=127.0.0.1
    export GOCLAW_PORT=${toString port}

    echo "${hostName} goclaw shell ready"
    echo "- Run goclaw as service user:  goclaw-admin pairing list"
    echo "- Approve a code:              goclaw-admin pairing approve ABCD12"
    echo "- Run Claude as goclaw user:   claude-goclaw"
    echo "- Edit ${hostName} secrets:         sops-${hostName}"
  '';
}
