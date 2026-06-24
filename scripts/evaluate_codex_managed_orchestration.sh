#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCOPE_PATH="${REPO_ROOT}/examples/hello-python"
RUN_ROOT="${ORCH_RUN_ROOT:-${REPO_ROOT}/orchestrator-codex}"

cat > "${SCOPE_PATH}/tests/test_placeholder.py" <<'EOF'
def test_placeholder():
    assert True
EOF

TASK="${1:-Edit tests/test_placeholder.py so it contains a deterministic assertion assert 1 + 1 == 2 and keep the file minimal.}"

ORCH_WORKER_MODE=auto ORCH_EXECUTE_WORKERS=1 bash "${SCRIPT_DIR}/orchestrate_codex_to_codex.sh" "$TASK" "$SCOPE_PATH"

LATEST_EXEC="$(find "$RUN_ROOT" -maxdepth 1 -type d -name 'run-*' | sort | tail -n 1)"
if [[ -n "${LATEST_EXEC:-}" && -f "${LATEST_EXEC}/summary.json" ]]; then
  echo ""
  echo "== Execution metrics =="
  jq '.worker_mode, .metrics' "${LATEST_EXEC}/summary.json"
  echo ""
  echo "== Updated test file =="
  cat "${SCOPE_PATH}/tests/test_placeholder.py"
  echo ""
  echo "Run directory: ${LATEST_EXEC}"
fi
