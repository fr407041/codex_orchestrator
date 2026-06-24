FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PLAYBOOK_ROOT=/opt/codex-claude-server-playbook

WORKDIR ${PLAYBOOK_ROOT}

COPY . ${PLAYBOOK_ROOT}

RUN chmod +x \
    ${PLAYBOOK_ROOT}/scripts/*.sh \
 && apt-get update \
 && apt-get install -y \
    ca-certificates \
    curl \
    git \
    jq \
    python3 \
    python3-pytest \
    python3-pip \
    python3-venv \
    gnupg \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
    >/etc/apt/sources.list.d/nodesource.list \
 && apt-get update \
 && apt-get install -y nodejs \
 && npm install -g @openai/codex \
 && mkdir -p /root/.codex \
 && cp ${PLAYBOOK_ROOT}/codex-config/config.toml.example /root/.codex/config.toml \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

ENV OPENAI_API_KEY=dummy-key
ENV OPENAI_BASE_URL=http://host.docker.internal:11434/v1
ENV MODEL_NAME=qwen3:4b
ENV ORCH_MAX_FILES_PER_JOB=2
ENV ORCH_MAX_JOBS=3
ENV ORCH_INVENTORY_LIMIT=12
ENV GUARD_MAX_FILES=2
ENV GUARD_MAX_LINES_PER_FILE=160
ENV GUARD_MAX_BATCHES=2

CMD ["/bin/bash"]
