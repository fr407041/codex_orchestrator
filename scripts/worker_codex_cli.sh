#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
JOB_FILE="${1:?Usage: worker_codex_cli.sh <job.json>}"

if [[ -z "${OPENAI_BASE_URL:-}" || -z "${MODEL_NAME:-}" ]]; then
  source "${SCRIPT_DIR}/resolve_model_env.sh"
fi

CODEX_BIN="${CODEX_BIN:-}"
if [[ -z "$CODEX_BIN" ]]; then
  if command -v codex >/dev/null 2>&1; then
    CODEX_BIN="$(command -v codex)"
  else
    echo "Codex CLI not found. Set CODEX_BIN or install codex." >&2
    exit 127
  fi
fi

JOB_JSON="$(python3 - "$JOB_FILE" <<'PY'
import json, sys
from pathlib import Path
print(json.dumps(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))))
PY
)"

JOB_ID="$(python3 - "$JOB_JSON" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("id", "job-001"))
PY
)"
SCOPE_PATH="$(python3 - "$JOB_JSON" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("scope_path", "."))
PY
)"
INSTRUCTION="$(python3 - "$JOB_JSON" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("instruction", "").strip())
PY
)"
SUCCESS_CHECK="$(python3 - "$JOB_JSON" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("success_check", "").strip())
PY
)"
TEST_COMMAND="$(python3 - "$JOB_JSON" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("test_command", "").strip())
PY
)"
REQUIRE_CHANGE="$(python3 - "$JOB_JSON" <<'PY'
import json, sys
print(str(bool(json.loads(sys.argv[1]).get("require_change", False))).lower())
PY
)"
FILES_JSON="$(python3 - "$JOB_JSON" <<'PY'
import json, sys
print(json.dumps(json.loads(sys.argv[1]).get("files", [])))
PY
)"
FILES_BULLETS="$(python3 - "$FILES_JSON" <<'PY'
import json, sys
for item in json.loads(sys.argv[1]):
    print(f"- {item}")
PY
)"

RESULTS_DIR="$(python3 - "$JOB_FILE" <<'PY'
import json, sys
from pathlib import Path
job_file = Path(sys.argv[1]).resolve()
run_dir = job_file.parent.parent
print(run_dir / "results")
PY
)"
mkdir -p "$RESULTS_DIR"

RAW_FILE="${RESULTS_DIR}/${JOB_ID}.raw.txt"
EXEC_LOG_FILE="${RESULTS_DIR}/${JOB_ID}.exec.log"
STATUS_FILE="${RESULTS_DIR}/${JOB_ID}.status.json"
TEST_OUTPUT_FILE="${RESULTS_DIR}/${JOB_ID}.test.txt"
BEFORE_FILE="${RESULTS_DIR}/${JOB_ID}.before.json"
AFTER_FILE="${RESULTS_DIR}/${JOB_ID}.after.json"

cd "$SCOPE_PATH"

python3 - "$FILES_JSON" "$BEFORE_FILE" <<'PY'
import hashlib, json, sys
from pathlib import Path
state = []
for rel in json.loads(sys.argv[1]):
    path = Path(rel)
    entry = {"path": rel, "exists": path.exists()}
    if path.exists() and path.is_file():
        entry["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    state.append(entry)
Path(sys.argv[2]).write_text(json.dumps(state, indent=2), encoding="utf-8")
PY

MODE_HINT="${WORKER_MODE_HINT:-normal}"
STRICT_NOTE=""
if [[ "$MODE_HINT" = "managed_single_file" ]]; then
  STRICT_NOTE=$'Additional hard rule:\n- Modify exactly one assigned file and do not create any extra files.\n'
fi

read -r -d '' PROMPT <<EOF || true
You are a low-context worker Codex agent.

Assigned files:
${FILES_BULLETS}

Task:
${INSTRUCTION}

Success check:
${SUCCESS_CHECK}

Rules:
- Only inspect or modify the assigned files.
- Keep output concise.
- If more files are needed, reply with NEEDS_REPLAN.
- If context pressure appears, reply with OVERFLOW_DETECTED.
- Do not browse broadly.
${STRICT_NOTE}
At the end, print one line exactly as:
WORKER_STATUS: <SUCCESS|NEEDS_REPLAN|OVERFLOW_DETECTED|FAILED>
EOF

export OPENAI_API_KEY="${OPENAI_API_KEY:-dummy-key}"

set +e
"$CODEX_BIN" exec \
  --skip-git-repo-check \
  -c "openai_base_url=\"${OPENAI_BASE_URL}\"" \
  -c 'model_provider="openai"' \
  -c "model=\"${MODEL_NAME}\"" \
  --output-last-message "$RAW_FILE" \
  --dangerously-bypass-approvals-and-sandbox \
  "$PROMPT" >"$EXEC_LOG_FILE" 2>&1
EXIT_CODE=$?
set -e

if [[ ! -f "$RAW_FILE" ]]; then
  : >"$RAW_FILE"
fi

python3 - "$FILES_JSON" "$AFTER_FILE" <<'PY'
import hashlib, json, sys
from pathlib import Path
state = []
for rel in json.loads(sys.argv[1]):
    path = Path(rel)
    entry = {"path": rel, "exists": path.exists()}
    if path.exists() and path.is_file():
        entry["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    state.append(entry)
Path(sys.argv[2]).write_text(json.dumps(state, indent=2), encoding="utf-8")
PY

ACTUAL_CHANGED_FILES="$(python3 - "$BEFORE_FILE" "$AFTER_FILE" <<'PY'
import json, sys
from pathlib import Path
before = {item["path"]: item for item in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))}
after = {item["path"]: item for item in json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))}
changed = []
for path, prev in before.items():
    curr = after.get(path, {})
    if prev.get("exists") != curr.get("exists") or prev.get("sha256") != curr.get("sha256"):
        changed.append(path)
print(json.dumps(changed))
PY
)"
ACTUAL_CHANGED_COUNT="$(python3 - "$ACTUAL_CHANGED_FILES" <<'PY'
import json, sys
print(len(json.loads(sys.argv[1])))
PY
)"

STATUS="SUCCESS"
if grep -Eiq 'WORKER_STATUS:\s*OVERFLOW_DETECTED|maximum context length|output tokens|token overflow|context window' "$RAW_FILE" "$EXEC_LOG_FILE"; then
  STATUS="OVERFLOW_DETECTED"
elif grep -Eiq 'WORKER_STATUS:\s*NEEDS_REPLAN' "$RAW_FILE" "$EXEC_LOG_FILE"; then
  STATUS="NEEDS_REPLAN"
elif grep -Eiq 'WORKER_STATUS:\s*FAILED' "$RAW_FILE" "$EXEC_LOG_FILE"; then
  STATUS="FAILED"
elif [[ "$EXIT_CODE" -ne 0 ]]; then
  STATUS="FAILED"
fi

TEST_EXIT_CODE=0
TEST_EXECUTED_COMMAND="$TEST_COMMAND"
if [[ -n "$TEST_COMMAND" && "$STATUS" = "SUCCESS" ]]; then
  set +e
  bash -lc "$TEST_COMMAND" >"$TEST_OUTPUT_FILE" 2>&1
  TEST_EXIT_CODE=$?
  set -e
fi

if [[ "$STATUS" = "SUCCESS" && "$REQUIRE_CHANGE" = "true" && "$ACTUAL_CHANGED_COUNT" -eq 0 ]]; then
  STATUS="FAILED"
fi
if [[ "$STATUS" = "SUCCESS" && -n "$TEST_COMMAND" && "$TEST_EXIT_CODE" -ne 0 ]]; then
  STATUS="FAILED"
fi

VERIFICATION_NOTE="verified"
if [[ "$REQUIRE_CHANGE" = "true" && "$ACTUAL_CHANGED_COUNT" -eq 0 ]]; then
  VERIFICATION_NOTE="claimed success without verified file change"
elif [[ -n "$TEST_COMMAND" && "$TEST_EXIT_CODE" -ne 0 ]]; then
  VERIFICATION_NOTE="file changed but verification command failed"
fi

jq -n \
  --arg id "$JOB_ID" \
  --arg status "$STATUS" \
  --arg scope_path "$SCOPE_PATH" \
  --argjson require_change "$REQUIRE_CHANGE" \
  --argjson files "$FILES_JSON" \
  --argjson actual_changed_files "$ACTUAL_CHANGED_FILES" \
  --arg verification_note "$VERIFICATION_NOTE" \
  --arg raw_file "$RAW_FILE" \
  --arg exec_log_file "$EXEC_LOG_FILE" \
  --arg test_command "$TEST_COMMAND" \
  --arg test_output_file "$TEST_OUTPUT_FILE" \
  --argjson exit_code "$EXIT_CODE" \
  --argjson actual_changed_count "$ACTUAL_CHANGED_COUNT" \
  --argjson test_exit_code "$TEST_EXIT_CODE" \
  '{
    id: $id,
    status: $status,
    scope_path: $scope_path,
    require_change: $require_change,
    files: $files,
    actual_changed_files: $actual_changed_files,
    actual_changed_count: $actual_changed_count,
    verification_note: $verification_note,
    raw_file: $raw_file,
    exec_log_file: $exec_log_file,
    test_command: $test_command,
    test_output_file: $test_output_file,
    exit_code: $exit_code,
    test_exit_code: $test_exit_code
  }' >"$STATUS_FILE"

cat "$RAW_FILE"
