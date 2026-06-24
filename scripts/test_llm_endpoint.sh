#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-auto}"

case "$TARGET" in
  auto)
    if eval "$("${SCRIPT_DIR}/detect_openai_compat_model.sh")"; then
      BASE_URL="${OPENAI_BASE_URL}"
    else
      exit 1
    fi
    ;;
  ollama)
    BASE_URL="${OPENAI_BASE_URL:-http://127.0.0.1:11434/v1}"
    ;;
  lmstudio)
    BASE_URL="${OPENAI_BASE_URL:-http://127.0.0.1:1234/v1}"
    ;;
  *)
    BASE_URL="$TARGET"
    ;;
esac

MODELS_URL="${BASE_URL%/}/models"

echo "Testing: ${MODELS_URL}"
curl -fsS "$MODELS_URL"
