#!/usr/bin/env bash
set -euo pipefail

pick_model() {
  python3 - <<'PY'
import json
import os
import re
import sys

payload = os.environ.get("MODELS_JSON", "")
if not payload:
    sys.exit(1)

try:
    data = json.loads(payload)
except json.JSONDecodeError:
    sys.exit(1)

models = []
for item in data.get("data", []):
    model_id = item.get("id")
    if isinstance(model_id, str) and model_id.strip():
        models.append(model_id.strip())

if not models:
    sys.exit(1)

def score(model: str):
    lowered = model.lower()
    score = 0
    if "coder" in lowered:
        score += 100
    if "code" in lowered:
        score += 60
    if "qwen2.5-coder" in lowered:
        score += 40
    if "qwen" in lowered:
        score += 20
    if "deepseek" in lowered:
        score += 18
    if "llama" in lowered:
        score += 12
    if "mistral" in lowered:
        score += 10
    if "gemma" in lowered:
        score -= 12
    match = re.search(r'(\d+(?:\.\d+)?)b', lowered)
    size_penalty = 0
    if match:
        size = float(match.group(1))
        if size <= 4:
            score += 16
        elif size <= 8:
            score += 10
        elif size <= 14:
            score += 4
        else:
            size_penalty = int(size)
    return (score - size_penalty, -len(model), model)

best = sorted(models, key=score, reverse=True)[0]
print(best)
PY
}

normalize_base_url() {
  local url="$1"
  printf '%s\n' "${url%/}"
}

fetch_models() {
  local base_url="$1"
  local models_url="${base_url%/}/models"
  curl -fsS --max-time "${MODEL_DETECT_TIMEOUT_SEC:-5}" "${models_url}"
}

declare -a candidates=()

if [[ -n "${OPENAI_BASE_URL:-}" ]]; then
  candidates+=("$(normalize_base_url "${OPENAI_BASE_URL}")")
fi

candidates+=(
  "http://host.docker.internal:11434/v1"
  "http://127.0.0.1:11434/v1"
  "http://host.docker.internal:1234/v1"
  "http://127.0.0.1:1234/v1"
)

declare -A seen=()

for candidate in "${candidates[@]}"; do
  [[ -n "${candidate}" ]] || continue
  if [[ -n "${seen[$candidate]:-}" ]]; then
    continue
  fi
  seen["$candidate"]=1

  if MODELS_JSON="$(fetch_models "$candidate" 2>/dev/null)"; then
    export MODELS_JSON
    if selected_model="$(pick_model 2>/dev/null)"; then
      printf 'export OPENAI_BASE_URL=%q\n' "$candidate"
      printf 'export MODEL_NAME=%q\n' "$selected_model"
      exit 0
    fi
  fi
done

cat >&2 <<'EOF'
Unable to auto-detect an OpenAI-compatible local model.
Checked common Ollama and LM Studio endpoints:
- http://host.docker.internal:11434/v1
- http://127.0.0.1:11434/v1
- http://host.docker.internal:1234/v1
- http://127.0.0.1:1234/v1

If your model service is elsewhere, set OPENAI_BASE_URL manually and retry.
EOF
exit 1
