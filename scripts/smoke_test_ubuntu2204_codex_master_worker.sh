#!/usr/bin/env bash
set -euo pipefail

PLAYBOOK_ROOT="${1:-/opt/codex-claude-server-playbook}"
MODEL_NAME="${MODEL_NAME:-qwen3:4b}"
BASE_URL="${OPENAI_BASE_URL:-http://127.0.0.1:11434/v1}"

if [[ ! -d "$PLAYBOOK_ROOT" ]]; then
  echo "Playbook root not found: $PLAYBOOK_ROOT" >&2
  exit 1
fi

export OPENAI_API_KEY="${OPENAI_API_KEY:-dummy-key}"
export OPENAI_BASE_URL="$BASE_URL"
export MODEL_NAME="$MODEL_NAME"

export ORCH_MAX_FILES_PER_JOB="${ORCH_MAX_FILES_PER_JOB:-2}"
export ORCH_MAX_JOBS="${ORCH_MAX_JOBS:-3}"
export ORCH_INVENTORY_LIMIT="${ORCH_INVENTORY_LIMIT:-12}"
export GUARD_MAX_FILES="${GUARD_MAX_FILES:-2}"
export GUARD_MAX_LINES_PER_FILE="${GUARD_MAX_LINES_PER_FILE:-160}"
export GUARD_MAX_BATCHES="${GUARD_MAX_BATCHES:-2}"

echo "== Codex version =="
codex --version
echo ""

echo "== Endpoint smoke test =="
bash "$PLAYBOOK_ROOT/scripts/test_llm_endpoint.sh" "$BASE_URL"
echo ""

echo "== Planning-only orchestration =="
ORCH_EXECUTE_WORKERS=0 bash "$PLAYBOOK_ROOT/scripts/orchestrate_codex_to_codex.sh" \
  "Inspect the hello-python repo, keep scope narrow, and return the smallest safe next task." \
  "$PLAYBOOK_ROOT/examples/hello-python"
echo ""

echo "== Worker edit execution =="
bash "$PLAYBOOK_ROOT/scripts/evaluate_codex_worker_edit.sh"
echo ""

echo "Smoke test complete."
