#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_FILE="${1:?Usage: worker_codex_managed_single_file.sh <job.json>}"

FILE_COUNT="$(python3 - "$JOB_FILE" <<'PY'
import json, sys
from pathlib import Path
job = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(len(job.get("files", [])))
PY
)"

if [[ "$FILE_COUNT" -ne 1 ]]; then
  echo "Managed single-file worker requires exactly one file." >&2
  exit 2
fi

export WORKER_MODE_HINT=managed_single_file
exec "${SCRIPT_DIR}/worker_codex_cli.sh" "$JOB_FILE"
