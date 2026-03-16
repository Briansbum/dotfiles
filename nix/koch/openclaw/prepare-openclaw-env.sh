#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: prepare-openclaw-env.sh <gateway_token_path> <openrouter_key_path> <telegram_token_path>" >&2
  exit 1
fi

gateway_token_path="$1"
openrouter_key_path="$2"
telegram_token_path="$3"

env_path="/run/openclaw/env"

umask 077
{
  printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$(cat "$gateway_token_path")"
  printf 'OPENAI_API_KEY=%s\n' "$(cat "$openrouter_key_path")"
  printf 'OPENAI_API_BASE=https://openrouter.ai/api/v1\n'
  printf 'OPENCLAW_TELEGRAM_BOT_TOKEN=%s\n' "$(cat "$telegram_token_path")"
} > "$env_path"
