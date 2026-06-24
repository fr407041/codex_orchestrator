#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLAYBOOK_ROOT="${1:-${REPO_ROOT}}"
MODELS="${MODELS:-qwen3:4b qwen2.5-coder:3b gemma3:4b}"
BENCH_ROOT="${PLAYBOOK_ROOT}/benchmarks"
RUN_ID="model-roles-$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${BENCH_ROOT}/${RUN_ID}"
mkdir -p "$RUN_DIR"

export OPENAI_API_KEY="${OPENAI_API_KEY:-dummy-key}"
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-http://127.0.0.1:11434/v1}"
export ORCH_MAX_FILES_PER_JOB="${ORCH_MAX_FILES_PER_JOB:-2}"
export ORCH_MAX_JOBS="${ORCH_MAX_JOBS:-3}"
export ORCH_INVENTORY_LIMIT="${ORCH_INVENTORY_LIMIT:-12}"
export GUARD_MAX_FILES="${GUARD_MAX_FILES:-2}"
export GUARD_MAX_LINES_PER_FILE="${GUARD_MAX_LINES_PER_FILE:-160}"
export GUARD_MAX_BATCHES="${GUARD_MAX_BATCHES:-2}"

RESULTS_TSV="${RUN_DIR}/results.tsv"
printf "model\tplanner_exit\tplanner_parse_ok\tworker_status\tworker_changed\tworker_test_exit\tnote\n" >"$RESULTS_TSV"

for model in $MODELS; do
  export MODEL_NAME="$model"

  planner_log="${RUN_DIR}/$(echo "$model" | tr ':/' '__').planner.json"
  worker_log="${RUN_DIR}/$(echo "$model" | tr ':/' '__').worker.json"

  ORCH_EXECUTE_WORKERS=0 bash "${SCRIPT_DIR}/orchestrate_codex_to_codex.sh" \
    "Inspect the hello-python repo, keep scope narrow, and return the smallest safe next task." \
    "${PLAYBOOK_ROOT}/examples/hello-python" >"$planner_log" 2>&1 || true

  bash "${SCRIPT_DIR}/evaluate_codex_worker_edit.sh" >"${RUN_DIR}/$(echo "$model" | tr ':/' '__').worker.txt" 2>&1 || true

  latest_worker_dir="$(find "${PLAYBOOK_ROOT}/orchestrator-codex/manual-worker-edit" -maxdepth 1 -type d -name 'run-*' | sort | tail -n 1)"
  latest_worker_status="${latest_worker_dir}/results/job-001.status.json"
  if [[ -f "$latest_worker_status" ]]; then
    cp "$latest_worker_status" "$worker_log"
  else
    printf '{}' >"$worker_log"
  fi

  planner_exit="$(python3 - "$planner_log" <<'PY'
import json, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
decoder = json.JSONDecoder()
objs = []
for i, ch in enumerate(text):
    if ch != "{":
        continue
    try:
        obj, _ = decoder.raw_decode(text[i:])
    except Exception:
        continue
    if isinstance(obj, dict) and "planner_exit" in obj:
        objs.append(obj)
print(objs[-1].get("planner_exit") if objs else "")
PY
)"
  planner_parse_ok="$(python3 - "$planner_log" <<'PY'
import json, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
decoder = json.JSONDecoder()
objs = []
for i, ch in enumerate(text):
    if ch != "{":
        continue
    try:
        obj, _ = decoder.raw_decode(text[i:])
    except Exception:
        continue
    if isinstance(obj, dict) and "planner_parse_ok" in obj:
        objs.append(obj)
print(objs[-1].get("planner_parse_ok") if objs else "")
PY
)"
  worker_status="$(jq -r '.status // ""' "$worker_log")"
  worker_changed="$(jq -r '.actual_changed_count // ""' "$worker_log")"
  worker_test_exit="$(jq -r '.test_exit_code // ""' "$worker_log")"
  worker_exec_log="$(jq -r '.exec_log_file // ""' "$worker_log")"

  note="unknown"
  if [[ -n "$worker_exec_log" && -f "$worker_exec_log" ]] && grep -q 'does not support tools' "$worker_exec_log" 2>/dev/null; then
    note="no_tool_support"
  elif grep -q 'does not support tools' "${RUN_DIR}/$(echo "$model" | tr ':/' '__').worker.txt" 2>/dev/null || grep -q 'does not support tools' "$planner_log" 2>/dev/null; then
    note="no_tool_support"
  elif [[ "$worker_status" = "FAILED" && "$worker_changed" = "0" ]]; then
    note="reply_only_no_real_edit"
  elif [[ "$worker_status" = "SUCCESS" && "$worker_changed" != "0" ]]; then
    note="real_edit_success"
  elif [[ "$worker_status" = "OVERFLOW_DETECTED" ]]; then
    note="overflow"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$model" "$planner_exit" "$planner_parse_ok" "$worker_status" "$worker_changed" "$worker_test_exit" "$note" >>"$RESULTS_TSV"
done

cat "$RESULTS_TSV"
