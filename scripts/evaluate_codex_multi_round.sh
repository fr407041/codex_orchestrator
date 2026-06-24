#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROUNDS="${1:-3}"
SCOPE_PATH="${2:-${REPO_ROOT}/examples/hello-python}"
TASK="${3:-Edit tests/test_placeholder.py so it contains a deterministic assertion assert 1 + 1 == 2 and keep the file minimal.}"
RUN_ROOT="${ORCH_RUN_ROOT:-${REPO_ROOT}/orchestrator-codex}"
REPORT_DIR="${REPO_ROOT}/benchmarks/multi-round-$(date +%Y%m%d-%H%M%S)}"
REPORT_FILE="${REPORT_DIR}/summary.tsv"

mkdir -p "$REPORT_DIR"
source "${SCRIPT_DIR}/resolve_model_env.sh"

printf "round\tmodel\tplanner_parse_ok\tworkers_failed\tworkers_overflowed\tworkers_need_replan\tworkers_false_success_blocked\tworkers_with_verified_changes\n" >"$REPORT_FILE"

for round in $(seq 1 "$ROUNDS"); do
  cat > "${SCOPE_PATH}/tests/test_placeholder.py" <<'EOF'
def test_placeholder():
    assert True
EOF

  ORCH_EXECUTE_WORKERS=1 bash "${SCRIPT_DIR}/orchestrate_codex_to_codex.sh" "$TASK" "$SCOPE_PATH" >/dev/null 2>&1 || true
  latest_run="$(find "$RUN_ROOT" -maxdepth 1 -type d -name 'run-*' | sort | tail -n 1)"
  summary_file="${latest_run}/summary.json"

  python3 - "$summary_file" "$round" "$MODEL_NAME" >>"$REPORT_FILE" <<'PY'
import json, sys
from pathlib import Path
summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
metrics = summary.get("metrics", {})
print("\t".join([
    sys.argv[2],
    sys.argv[3],
    str(summary.get("planner_parse_ok")),
    str(metrics.get("workers_failed")),
    str(metrics.get("workers_overflowed")),
    str(metrics.get("workers_need_replan")),
    str(metrics.get("workers_false_success_blocked")),
    str(metrics.get("workers_with_verified_changes")),
]))
PY
done

cat "$REPORT_FILE"
