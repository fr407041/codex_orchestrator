#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${OPENAI_BASE_URL:-}" && -n "${MODEL_NAME:-}" ]]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

eval "$("${SCRIPT_DIR}/detect_openai_compat_model.sh")"

model_lower="$(printf '%s' "${MODEL_NAME}" | tr '[:upper:]' '[:lower:]')"

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  export OPENAI_API_KEY="dummy-key"
fi

if [[ -z "${ORCH_MAX_FILES_PER_JOB:-}" ]]; then
  export ORCH_MAX_FILES_PER_JOB=2
fi
if [[ -z "${ORCH_MAX_JOBS:-}" ]]; then
  export ORCH_MAX_JOBS=3
fi
if [[ -z "${ORCH_INVENTORY_LIMIT:-}" ]]; then
  export ORCH_INVENTORY_LIMIT=12
fi
if [[ -z "${GUARD_MAX_FILES:-}" ]]; then
  export GUARD_MAX_FILES=2
fi
if [[ -z "${GUARD_MAX_LINES_PER_FILE:-}" ]]; then
  export GUARD_MAX_LINES_PER_FILE=160
fi
if [[ -z "${GUARD_MAX_BATCHES:-}" ]]; then
  export GUARD_MAX_BATCHES=2
fi
if [[ -z "${API_TIMEOUT_MS:-}" ]]; then
  export API_TIMEOUT_MS=600000
fi

if [[ "${model_lower}" == *"3b"* || "${model_lower}" == *"4b"* ]]; then
  if (( ORCH_MAX_FILES_PER_JOB > 1 )); then
    export ORCH_MAX_FILES_PER_JOB=1
  fi
  if (( ORCH_MAX_JOBS > 2 )); then
    export ORCH_MAX_JOBS=2
  fi
  if (( ORCH_INVENTORY_LIMIT > 8 )); then
    export ORCH_INVENTORY_LIMIT=8
  fi
  if (( GUARD_MAX_FILES > 1 )); then
    export GUARD_MAX_FILES=1
  fi
  if (( GUARD_MAX_LINES_PER_FILE > 120 )); then
    export GUARD_MAX_LINES_PER_FILE=120
  fi
  if (( GUARD_MAX_BATCHES > 1 )); then
    export GUARD_MAX_BATCHES=1
  fi
fi
