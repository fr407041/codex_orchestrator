# Ubuntu 22.04 Codex Master-Worker Image

This folder provides a rebuildable Ubuntu 22.04 container for:

- `master codex` planning
- `worker codex` execution
- open-source / local OpenAI-compatible LLM endpoints
- safer defaults for smaller models to reduce token overflow

## Build

```bash
cd /opt/codex-claude-server-playbook/ubuntu22.04
docker compose build
```

## Start a shell

```bash
docker compose run --rm codex-master-worker
```

## Inside the container

```bash
cd /opt/codex-claude-server-playbook
bash ./scripts/test_llm_endpoint.sh
bash ./scripts/smoke_test_ubuntu2204_codex_master_worker.sh /opt/codex-claude-server-playbook
```

## Default assumptions

- LLM endpoint: `http://host.docker.internal:11434/v1`
- API key: `dummy-key`
- model: `qwen3:4b`
- very small planning batches to reduce overflow

## If your model is larger

You can raise:

- `ORCH_MAX_FILES_PER_JOB`
- `ORCH_INVENTORY_LIMIT`
- `GUARD_MAX_LINES_PER_FILE`

But increase them gradually and watch:

- `workers_overflowed`
- `overflow_retries`
- `workers_need_replan`
