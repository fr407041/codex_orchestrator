#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="${REPO_ROOT}/examples/hello-python"
RUN_ROOT="${REPO_ROOT}/orchestrator-codex/manual-worker-edit"
RUN_ID="run-$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${RUN_ROOT}/${RUN_ID}"
JOBS_DIR="${RUN_DIR}/jobs"
RESULTS_DIR="${RUN_DIR}/results"

mkdir -p "$JOBS_DIR" "$RESULTS_DIR"
cd "$PROJECT_ROOT"

cat > tests/test_placeholder.py <<'EOF'
def test_placeholder():
    assert True
EOF

cat > "${JOBS_DIR}/job-001.json" <<'EOF'
{
  "id": "job-001",
  "scope_path": "__PROJECT_ROOT__",
  "title": "Add a stronger placeholder assertion",
  "instruction": "Edit tests/test_placeholder.py so it contains a deterministic assertion assert 1 + 1 == 2 and keep the file minimal.",
  "files": [
    "tests/test_placeholder.py"
  ],
  "success_check": "tests/test_placeholder.py contains assert 1 + 1 == 2 and pytest -q passes",
  "require_change": true,
  "test_command": "pytest -q"
}
EOF

sed -i "s|__PROJECT_ROOT__|${PROJECT_ROOT}|g" "${JOBS_DIR}/job-001.json"

bash "${SCRIPT_DIR}/worker_codex_cli.sh" "${JOBS_DIR}/job-001.json" >/dev/null || true

STATUS_FILE="${RESULTS_DIR}/job-001.status.json"
TEST_FILE="${PROJECT_ROOT}/tests/test_placeholder.py"

echo "== Worker edit status =="
jq . "$STATUS_FILE"
echo ""
echo "== Updated test file =="
cat "$TEST_FILE"

if [[ -f "${RESULTS_DIR}/job-001.test.txt" ]]; then
  echo ""
  echo "== pytest output =="
  cat "${RESULTS_DIR}/job-001.test.txt"
fi
