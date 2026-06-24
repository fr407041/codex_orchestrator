#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME="${MODEL_NAME:-qwen3:4b}"
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

if [[ $# -gt 0 ]]; then
  exec "$CODEX_BIN" exec --oss --local-provider ollama --model "$MODEL_NAME" --dangerously-bypass-approvals-and-sandbox "$@"
fi

exec "$CODEX_BIN" --oss --local-provider ollama --model "$MODEL_NAME"
