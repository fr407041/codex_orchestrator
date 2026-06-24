#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TASK="${1:-Inspect the hello-python repo, find the smallest next code task, and keep scope narrow.}"
SCOPE_PATH="${2:-${REPO_ROOT}/examples/hello-python}"
RUN_ROOT="${ORCH_RUN_ROOT:-${REPO_ROOT}/orchestrator-codex}"

echo "== Planning-only evaluation =="
ORCH_EXECUTE_WORKERS=0 bash "${SCRIPT_DIR}/orchestrate_codex_to_codex.sh" "$TASK" "$SCOPE_PATH"

LATEST_PLAN="$(find "$RUN_ROOT" -maxdepth 1 -type d -name 'run-*' | sort | tail -n 1)"
if [[ -n "${LATEST_PLAN:-}" && -f "${LATEST_PLAN}/summary.json" ]]; then
  echo ""
  echo "== Planning metrics =="
  jq '.metrics' "${LATEST_PLAN}/summary.json"
fi

echo ""
echo "== Worker execution evaluation =="
ORCH_EXECUTE_WORKERS=1 bash "${SCRIPT_DIR}/orchestrate_codex_to_codex.sh" "$TASK" "$SCOPE_PATH"

LATEST_EXEC="$(find "$RUN_ROOT" -maxdepth 1 -type d -name 'run-*' | sort | tail -n 1)"
if [[ -n "${LATEST_EXEC:-}" && -f "${LATEST_EXEC}/summary.json" ]]; then
  echo ""
  echo "== Execution metrics =="
  jq '.metrics' "${LATEST_EXEC}/summary.json"
  echo ""
  echo "Run directory: ${LATEST_EXEC}"
fi
