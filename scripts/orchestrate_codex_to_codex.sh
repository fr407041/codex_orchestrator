#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TASK="${1:?Usage: orchestrate_codex_to_codex.sh <task> [scope_path]}"
SCOPE_PATH="${2:-${REPO_ROOT}}"

if [[ -z "${OPENAI_BASE_URL:-}" || -z "${MODEL_NAME:-}" ]]; then
  source "${SCRIPT_DIR}/resolve_model_env.sh"
fi

MAX_FILES_PER_JOB="${ORCH_MAX_FILES_PER_JOB:-2}"
MAX_JOBS="${ORCH_MAX_JOBS:-3}"
INVENTORY_LIMIT="${ORCH_INVENTORY_LIMIT:-12}"
EXECUTE_WORKERS="${ORCH_EXECUTE_WORKERS:-1}"
RUN_ROOT="${ORCH_RUN_ROOT:-${REPO_ROOT}/orchestrator-codex}"
RUN_ID="${ORCH_RUN_ID:-run-$(date +%Y%m%d-%H%M%S)}"
RUN_DIR="${RUN_ROOT}/${RUN_ID}"
JOBS_DIR="${RUN_DIR}/jobs"
RESULTS_DIR="${RUN_DIR}/results"
mkdir -p "$JOBS_DIR" "$RESULTS_DIR"

INVENTORY_FILE="${RUN_DIR}/inventory.txt"
COMPACT_FILE="${RUN_DIR}/inventory.compact.txt"
PLAN_RAW_FILE="${RUN_DIR}/planner.raw.txt"
PLAN_JSON_FILE="${RUN_DIR}/plan.json"
SUMMARY_FILE="${RUN_DIR}/summary.json"

python3 - "$SCOPE_PATH" <<'PY' >"$INVENTORY_FILE"
import os, sys
scope = os.path.abspath(sys.argv[1])
skip_dirs = {".git", "node_modules", ".venv", "venv", "__pycache__", ".pytest_cache", "dist", "build", "orchestrator-codex"}
allowed_ext = {".py", ".js", ".ts", ".tsx", ".jsx", ".json", ".md", ".yml", ".yaml", ".sh", ".ps1", ".toml", ".ini", ".cfg", ".txt"}
for root, dirs, files in os.walk(scope):
    dirs[:] = [d for d in dirs if d not in skip_dirs]
    for name in sorted(files):
        path = os.path.join(root, name)
        rel = os.path.relpath(path, scope).replace("\\", "/")
        _, ext = os.path.splitext(name)
        if ext.lower() in allowed_ext or name in {"Dockerfile", "Makefile"}:
            print(rel)
PY

TOTAL_FILES="$(wc -l <"$INVENTORY_FILE" | tr -d ' ')"
head -n "$INVENTORY_LIMIT" "$INVENTORY_FILE" >"$COMPACT_FILE"
COMPACT_COUNT="$(wc -l <"$COMPACT_FILE" | tr -d ' ')"

DIRECT_PLAN_GENERATED=1
python3 - "$TASK" "$INVENTORY_FILE" "$PLAN_JSON_FILE" <<'PY' || DIRECT_PLAN_GENERATED=0
import json, sys
from pathlib import Path

task = sys.argv[1].lower()
inventory = [line.strip() for line in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines() if line.strip()]
target = []
for rel in inventory:
    name = Path(rel).name.lower()
    if rel.lower() in task or name in task:
        target.append(rel)
target = list(dict.fromkeys(target))
if len(target) != 1:
    sys.exit(1)
Path(sys.argv[3]).write_text(json.dumps({
    "strategy": "Deterministic single-file managed edit because the task explicitly names one target file.",
    "jobs": [{
        "title": f"Managed edit for {target[0]}",
        "instruction": sys.argv[1],
        "files": [target[0]],
        "success_check": f"{target[0]} is updated exactly as requested."
    }]
}, indent=2), encoding="utf-8")
PY

if [[ "$DIRECT_PLAN_GENERATED" = "0" ]]; then
  PLANNER_PROMPT="$(cat <<EOF
Return JSON only.

Split the task into at most ${MAX_JOBS} very small worker jobs for a smaller local coding model.
Each job may reference at most ${MAX_FILES_PER_JOB} files.
Use only files from this inventory sample.
If the task is broad, prefer investigation jobs first.

Task:
${TASK}

Inventory sample (${COMPACT_COUNT} of ${TOTAL_FILES} files):
$(cat "$COMPACT_FILE")

Schema:
{
  \"strategy\": \"one short sentence\",
  \"jobs\": [
    {
      \"title\": \"short title\",
      \"instruction\": \"specific instruction\",
      \"files\": [\"path1\"],
      \"success_check\": \"specific success condition\"
    }
  ]
}
EOF
)"

  set +e
  bash "${SCRIPT_DIR}/run_codex_guarded.sh" "$PLANNER_PROMPT" >"$PLAN_RAW_FILE" 2>&1
  set -e

  set +e
  python3 - "$PLAN_RAW_FILE" "$PLAN_JSON_FILE" "$MAX_FILES_PER_JOB" "$MAX_JOBS" <<'PY'
import json, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
decoder = json.JSONDecoder()
selected = None
for idx, ch in enumerate(text):
    if ch != "{":
        continue
    try:
        obj, _ = decoder.raw_decode(text[idx:])
    except json.JSONDecodeError:
        continue
    if isinstance(obj, dict) and isinstance(obj.get("jobs"), list):
        selected = obj
if not selected:
    sys.exit(1)
selected["jobs"] = selected["jobs"][: int(sys.argv[4])]
for job in selected["jobs"]:
    job["files"] = job.get("files", [])[: int(sys.argv[3])]
Path(sys.argv[2]).write_text(json.dumps(selected, indent=2), encoding="utf-8")
PY
  PLANNER_PARSE_OK=$?
  set -e
else
  PLANNER_PARSE_OK=0
fi

if [[ ! -f "$PLAN_JSON_FILE" || "$PLANNER_PARSE_OK" -ne 0 ]]; then
  python3 - "$COMPACT_FILE" "$PLAN_JSON_FILE" "$MAX_FILES_PER_JOB" "$MAX_JOBS" "$TASK" <<'PY'
import json, sys
from pathlib import Path
files = [line.strip() for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
max_files = int(sys.argv[3])
max_jobs = int(sys.argv[4])
jobs = []
for idx in range(0, min(len(files), max_files * max_jobs), max_files):
    chunk = files[idx: idx + max_files]
    jobs.append({
        "title": f"Fallback batch {len(jobs) + 1}",
        "instruction": f"{sys.argv[5]} Limit work strictly to the assigned files.",
        "files": chunk,
        "success_check": "Return a concise result for only the assigned files."
    })
Path(sys.argv[2]).write_text(json.dumps({
    "strategy": "Fallback deterministic batching because planner JSON was unavailable.",
    "jobs": jobs
}, indent=2), encoding="utf-8")
PY
fi

python3 - "$PLAN_JSON_FILE" "$JOBS_DIR" "$SCOPE_PATH" <<'PY'
import json, sys
from pathlib import Path
plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
jobs_dir = Path(sys.argv[2])
scope_path = sys.argv[3]
for idx, job in enumerate(plan.get("jobs", []), start=1):
    payload = {
        "id": f"job-{idx:03d}",
        "scope_path": scope_path,
        "title": job.get("title", f"job-{idx:03d}"),
        "instruction": job.get("instruction", ""),
        "files": job.get("files", []),
        "success_check": job.get("success_check", ""),
        "require_change": any(word in job.get("instruction", "").lower() for word in ["edit", "fix", "modify", "write", "update", "create", "replace"]),
        "test_command": "python3 -m pytest -q" if any(str(item).startswith("tests/") for item in job.get("files", [])) else ""
    }
    (jobs_dir / f"job-{idx:03d}.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
PY

WORKERS_RUN=0
WORKERS_OVERFLOWED=0
WORKERS_FAILED=0
WORKERS_NEED_REPLAN=0
WORKERS_FALSE_SUCCESS_BLOCKED=0
WORKERS_WITH_VERIFIED_CHANGES=0

if [[ "$EXECUTE_WORKERS" = "1" ]]; then
  for job_file in "$JOBS_DIR"/job-*.json; do
    [[ -f "$job_file" ]] || continue
    WORKERS_RUN=$((WORKERS_RUN + 1))
    file_count="$(jq '.files | length' "$job_file")"
    if [[ "$file_count" -eq 1 ]]; then
      bash "${SCRIPT_DIR}/worker_codex_managed_single_file.sh" "$job_file" >/dev/null || true
    else
      bash "${SCRIPT_DIR}/worker_codex_cli.sh" "$job_file" >/dev/null || true
    fi
    status_file="${RESULTS_DIR}/$(basename "${job_file%.json}").status.json"
    status="$(jq -r '.status' "$status_file")"
    changed="$(jq -r '.actual_changed_count // 0' "$status_file")"
    note="$(jq -r '.verification_note // empty' "$status_file")"
    if [[ "$status" = "OVERFLOW_DETECTED" ]]; then
      WORKERS_OVERFLOWED=$((WORKERS_OVERFLOWED + 1))
    elif [[ "$status" = "NEEDS_REPLAN" ]]; then
      WORKERS_NEED_REPLAN=$((WORKERS_NEED_REPLAN + 1))
    elif [[ "$status" = "FAILED" ]]; then
      WORKERS_FAILED=$((WORKERS_FAILED + 1))
    fi
    if [[ "$changed" -gt 0 ]]; then
      WORKERS_WITH_VERIFIED_CHANGES=$((WORKERS_WITH_VERIFIED_CHANGES + 1))
    fi
    if [[ "$note" = "claimed success without verified file change" ]]; then
      WORKERS_FALSE_SUCCESS_BLOCKED=$((WORKERS_FALSE_SUCCESS_BLOCKED + 1))
    fi
  done
fi

MAX_FILES_IN_JOB="$(python3 - "$JOBS_DIR" <<'PY'
import json, sys
from pathlib import Path
counts = []
for path in Path(sys.argv[1]).glob("job-*.json"):
    counts.append(len(json.loads(path.read_text(encoding="utf-8")).get("files", [])))
print(max(counts) if counts else 0)
PY
)"

jq -n \
  --arg run_id "$RUN_ID" \
  --arg task "$TASK" \
  --arg scope_path "$SCOPE_PATH" \
  --arg strategy "$(jq -r '.strategy' "$PLAN_JSON_FILE")" \
  --arg planner_raw_file "$PLAN_RAW_FILE" \
  --arg plan_json_file "$PLAN_JSON_FILE" \
  --arg jobs_dir "$JOBS_DIR" \
  --arg results_dir "$RESULTS_DIR" \
  --argjson total_files "$TOTAL_FILES" \
  --argjson compact_inventory_files "$COMPACT_COUNT" \
  --argjson planner_parse_ok "$PLANNER_PARSE_OK" \
  --argjson workers_run "$WORKERS_RUN" \
  --argjson workers_overflowed "$WORKERS_OVERFLOWED" \
  --argjson workers_failed "$WORKERS_FAILED" \
  --argjson workers_need_replan "$WORKERS_NEED_REPLAN" \
  --argjson workers_false_success_blocked "$WORKERS_FALSE_SUCCESS_BLOCKED" \
  --argjson workers_with_verified_changes "$WORKERS_WITH_VERIFIED_CHANGES" \
  --argjson max_files_in_job "$MAX_FILES_IN_JOB" \
  '{
    run_id: $run_id,
    task: $task,
    scope_path: $scope_path,
    strategy: $strategy,
    planner_parse_ok: ($planner_parse_ok == 0),
    planner_raw_file: $planner_raw_file,
    plan_json_file: $plan_json_file,
    jobs_dir: $jobs_dir,
    results_dir: $results_dir,
    metrics: {
      total_files_in_scope: $total_files,
      compact_inventory_files: $compact_inventory_files,
      workers_run: $workers_run,
      workers_overflowed: $workers_overflowed,
      workers_failed: $workers_failed,
      workers_need_replan: $workers_need_replan,
      workers_false_success_blocked: $workers_false_success_blocked,
      workers_with_verified_changes: $workers_with_verified_changes,
      max_files_in_job: $max_files_in_job
    }
  }' >"$SUMMARY_FILE"

jq . "$SUMMARY_FILE"
