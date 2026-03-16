# OpenClaw configuration for macOS (Alexs-MacBook-Pro)
#
# Mirrors koch's security posture: telegram-only, plugins disabled, local gateway.
# Secrets are read from files at runtime — never stored in the Nix store.
#
# To populate secrets (one-time setup):
#   mkdir -p ~/.openclaw/secrets && chmod 700 ~/.openclaw/secrets
#   op read "op://Personal/openclaw-telegram-token/credential" > ~/.openclaw/secrets/telegram-token
#   op read "op://Personal/openclaw-gateway-token/credential"  > ~/.openclaw/secrets/gateway-token
#   op read "op://Personal/openclaw-openrouter-key/credential"  > ~/.openclaw/secrets/openrouter-key
#   chmod 400 ~/.openclaw/secrets/*

{ config, pkgs, lib, ... }:

let
  secretsDir = "${config.home.homeDirectory}/.openclaw/secrets";
in
{
  programs.openclaw = {
    enable = true;
    installApp = false;

    # Disable bundled plugins that default to enabled (goplaces)
    # All others already default to false; config.plugins.enabled = false
    # also disables plugin loading at the gateway level.
    bundledPlugins.goplaces.enable = false;

    instances.default = {
      launchd.enable = true;

      config = {
        # Disable plugins entirely — same as koch
        plugins = {
          enabled = false;
        };

        # Local-only gateway, bound to loopback
        gateway = {
          mode = "local";
          bind = "loopback";

          # Token auth with file-based secret (never in nix store)
          auth = {
            mode = "token";
            token = {
              source = "file";
              provider = "local";
              id = "${secretsDir}/gateway-token";
            };
            # Rate-limit brute-force attempts
            rateLimit = {
              maxAttempts = 5;
              windowMs = 60000;
              lockoutMs = 300000;
            };
          };

          # Disable the control UI — headless, telegram-only
          controlUi = {
            enabled = false;
          };
        };

        # Telegram-only channel — same allowlist as koch
        channels.telegram = {
          tokenFile = "${secretsDir}/telegram-token";
          allowFrom = [
            560918177
          ];
        };
      };
    };
  };

  # Ensure secrets directory exists with restrictive permissions
  home.activation.openclawSecrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run --quiet ${lib.getExe' pkgs.coreutils "mkdir"} -p "${secretsDir}"
    run --quiet ${lib.getExe' pkgs.coreutils "chmod"} 700 "${secretsDir}"
  '';
}
