#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME="${MODEL_NAME:-qwen3:4b}"
BASE_URL="${OPENAI_BASE_URL:-http://127.0.0.1:11434/v1}"
CODEX_BIN="${CODEX_BIN:-}"

if [[ -z "$CODEX_BIN" ]]; then
  if command -v codex > /dev/null 2>&1; then
    CODEX_BIN="$(command -v codex)"
  elif [[ -x /usr/local/bin/run-codex ]]; then
    CODEX_BIN="/usr/local/bin/run-codex"
  else
    echo "Codex CLI not found. Set CODEX_BIN or install codex." >&2
    exit 127
  fi
fi

export OPENAI_API_KEY="${OPENAI_API_KEY:-dummy-key}"

if [[ $# -gt 0 ]]; then
  exec "$CODEX_BIN" exec \
    --skip-git-repo-check \
    -c "openai_base_url=\"$BASE_URL\"" \
    -c 'model_provider="openai"' \
    -c "model=\"$MODEL_NAME\"" \
    --dangerously-bypass-approvals-and-sandbox \
    "$@"
fi

exec "$CODEX_BIN" \
  -c "openai_base_url=\"$BASE_URL\"" \
  -c 'model_provider="openai"' \
  -c "model=\"$MODEL_NAME\""
