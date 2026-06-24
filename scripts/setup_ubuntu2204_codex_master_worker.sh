#!/usr/bin/env bash
set -euo pipefail

PLAYBOOK_ROOT="${1:-/opt/codex-claude-server-playbook}"
NODE_MAJOR="${NODE_MAJOR:-20}"
INSTALL_CLAUDE_OPTIONAL="${INSTALL_CLAUDE_OPTIONAL:-0}"

export DEBIAN_FRONTEND=noninteractive

if [[ ! -d "$PLAYBOOK_ROOT" ]]; then
  echo "Playbook root not found: $PLAYBOOK_ROOT" >&2
  echo "Copy this repository folder into the Ubuntu 22.04 image first." >&2
  exit 1
fi

apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  git \
  jq \
  python3 \
  python3-pytest \
  python3-pip \
  python3-venv \
  gnupg

mkdir -p /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/nodesource.gpg ]]; then
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
fi
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
  >/etc/apt/sources.list.d/nodesource.list

apt-get update
apt-get install -y nodejs
apt-get clean
rm -rf /var/lib/apt/lists/*

npm install -g @openai/codex

if [[ "$INSTALL_CLAUDE_OPTIONAL" = "1" ]]; then
  npm install -g @anthropic-ai/claude-code @musistudio/claude-code-router
fi

mkdir -p /root/.codex
if [[ ! -f /root/.codex/config.toml ]]; then
  cp "$PLAYBOOK_ROOT/codex-config/config.toml.example" /root/.codex/config.toml
fi

cat <<EOF
Ubuntu 22.04 Codex master-worker bootstrap complete.

Installed:
- node: $(node -v)
- npm: $(npm -v)
- codex: $(codex --version)

Next:
1. Export OPENAI_API_KEY=dummy-key
2. Export OPENAI_BASE_URL to your OpenAI-compatible local model endpoint
3. Optional: source $PLAYBOOK_ROOT/profiles/qwen-small-safe.env.example values manually
4. Run:
   bash $PLAYBOOK_ROOT/scripts/test_llm_endpoint.sh
   bash $PLAYBOOK_ROOT/scripts/smoke_test_ubuntu2204_codex_master_worker.sh $PLAYBOOK_ROOT
EOF
