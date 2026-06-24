# Ubuntu 22.04 Image 安裝指引

這份指引是給「已經有 Ubuntu 22.04 image / container」的情境，目標是讓裡面的 `Codex` 能用開源 LLM，並在 container 內執行：

- `master codex` 規劃與拆 job
- `worker codex cli` 執行小 job
- 盡量避免 token overflow

## 適用前提

你至少要有其中一種模型服務：

1. 同一個 container / VM 內的 Ollama
2. 同主機其他 service 提供的 OpenAI-compatible API
3. Docker host 上的 Ollama / LM Studio

## 建議的 endpoint

### 模型在同一個 Ubuntu 環境

```bash
export OPENAI_BASE_URL=http://127.0.0.1:11434/v1
```

### 模型在 Docker host

```bash
export OPENAI_BASE_URL=http://host.docker.internal:11434/v1
```

如果 `host.docker.internal` 不通，container 啟動時補：

```bash
--add-host=host.docker.internal:host-gateway
```

## 安裝步驟

先把這份 playbook 放進 image / container，例如：

```bash
/opt/codex-claude-server-playbook
```

然後執行：

```bash
cd /opt/codex-claude-server-playbook
bash ./scripts/setup_ubuntu2204_codex_master_worker.sh /opt/codex-claude-server-playbook
```

如果你想直接重建一個可重複使用的 Ubuntu 22.04 image，也可以直接用這份資料夾內建的：

```bash
cd /opt/codex-claude-server-playbook/ubuntu22.04
docker compose build
docker compose run --rm codex-master-worker
```

## 小模型安全參數

如果你先用 `qwen3:4b`、`qwen2.5-coder:7b` 這類較小模型，建議先套保守參數：

```bash
source /opt/codex-claude-server-playbook/profiles/qwen-small-safe.env.example
```

如果你不想直接 `source` 範例檔，也可以手動 export 同內容。

## 驗證順序

### 1. 測 endpoint

```bash
export OPENAI_API_KEY=dummy-key
bash /opt/codex-claude-server-playbook/scripts/test_llm_endpoint.sh
```

### 2. 跑整體 smoke test

```bash
bash /opt/codex-claude-server-playbook/scripts/smoke_test_ubuntu2204_codex_master_worker.sh \
  /opt/codex-claude-server-playbook
```

### 3. 單獨跑 master -> worker

```bash
bash /opt/codex-claude-server-playbook/scripts/orchestrate_codex_to_codex.sh \
  "Inspect the repo, identify the smallest safe next code task, and avoid broad reads." \
  /opt/codex-claude-server-playbook/examples/hello-python
```

## 如何判斷是否比較不容易 overflow

看每次 run 產出的 `summary.json`：

- `max_files_in_job` 是否維持在 1 到 2
- `workers_overflowed` 是否接近 0
- `overflow_retries` 是否沒有持續升高
- `workers_need_replan` 是否可接受
- `workers_false_success_blocked` 是否為 0

## 給開源 Codex 的精簡指令

若你要把規則直接丟給另一個 Codex，可先給他看：

```bash
cat /opt/codex-claude-server-playbook/prompts/master_codex_bootstrap.zh-TW.md
```

如果你希望用英文、而且內容更短更像 machine-readable bootstrap，也可給他：

```bash
cat /opt/codex-claude-server-playbook/ubuntu22.04/CODEX_BOOTSTRAP.en.md
```

## 2026-06-24 實測狀態

請搭配閱讀：

- `ubuntu22.04/VERIFIED_RESULTS_2026-06-24.zh-TW.md`
- `ubuntu22.04/MODEL_ROLE_MATRIX_2026-06-24.zh-TW.md`

目前已實測確認：

1. image 可 build
2. container 可連到 host 的 Ollama OpenAI-compatible API
3. master codex 規劃可用
4. direct child codex edit 目前仍可能「口頭成功但未真改檔」
5. `qwen2.5-coder:3b` 已可走 managed single-file child edit

所以現階段最穩的定位是：

- `master codex for planning`
- `child codex for inspection-first`
- 單檔 edit 用 `managed single-file worker`
- edit 任務一定要保留 verification gate

如果你要自己重跑角色測試，可在 container 內執行：

```bash
bash /opt/codex-claude-server-playbook/scripts/benchmark_model_roles.sh \
  /opt/codex-claude-server-playbook
```

如果你要直接驗證目前最強已測通路徑，可在 container 內執行：

```bash
MODEL_NAME=qwen2.5-coder:3b \
bash /opt/codex-claude-server-playbook/scripts/evaluate_codex_managed_orchestration.sh
```

## 注意

1. 這份流程是讓小模型比較不容易爆 context，不保證完全不 overflow。
2. 若 `qwen3:4b` 仍不穩，先把 `ORCH_MAX_FILES_PER_JOB` 再降到 1。
3. 若 worker 常常只會說明不會改檔，請優先看 `workers_false_success_blocked`。
