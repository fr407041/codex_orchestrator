# Codex Server Playbook

這份是 Linux server 內部使用版，主路徑改成：

- `master codex` 用開源 / 本機 LLM 做規劃與拆 job
- `worker codex cli` 也用開源 / 本機 LLM 執行小 job
- `Claude Code + router` 保留為替代路徑，但不是這版主流程

這份說明不依賴 Docker image，假設你已經能在 server 上直接執行 `codex`，且本機或同機房已有 OpenAI-compatible 開源模型服務。

## 核心概念

1. `Codex master` 只做窄範圍 inventory、規劃、拆 job。
2. `Codex worker` 每次只吃極少數檔案，避免大 prompt 直接打爆 context。
3. `worker` 若偵測上下文壓力，回傳 `OVERFLOW_DETECTED`。
4. `worker` 若缺額外檔案，回傳 `NEEDS_REPLAN`。
5. edit 任務一定驗證實際檔案變更與測試結果，避免假成功。

## 主要檔案

### Codex-only 主流程

- `scripts/run_codex_guarded.sh`
- `scripts/run_codex_openai_compat.sh`
- `scripts/orchestrate_codex_to_codex.sh`
- `scripts/worker_codex_cli.sh`
- `scripts/evaluate_codex_orchestration.sh`
- `scripts/evaluate_codex_worker_edit.sh`
- `scripts/setup_ubuntu2204_codex_master_worker.sh`
- `scripts/smoke_test_ubuntu2204_codex_master_worker.sh`
- `scripts/test_llm_endpoint.sh`
- `profiles/qwen-small-safe.env.example`
- `prompts/master_codex_bootstrap.zh-TW.md`
- `ubuntu22.04/INSTALL.zh-TW.md`
- `ubuntu22.04/Dockerfile`
- `ubuntu22.04/docker-compose.yml`
- `ubuntu22.04/README.en.md`
- `ubuntu22.04/CODEX_BOOTSTRAP.en.md`
- `ubuntu22.04/VERIFIED_RESULTS_2026-06-24.zh-TW.md`
- `ubuntu22.04/MODEL_ROLE_MATRIX_2026-06-24.zh-TW.md`
- `codex-config/config.toml.example`
- `codex-config/config.oss.example.toml`
- `examples/hello-python/`
- `scripts/benchmark_model_roles.sh`
- `scripts/worker_codex_managed_single_file.sh`
- `scripts/evaluate_codex_managed_worker_edit.sh`
- `scripts/evaluate_codex_managed_orchestration.sh`

### 保留的 Claude/router 替代流程

- `router-config.json`
- `run-claude.sh`
- `run-codex.sh`
- `start-ccr.sh`
- `scripts/orchestrate_codex_to_claude.sh`
- `scripts/worker_claude_router.sh`
- `scripts/evaluate_orchestration.sh`
- `scripts/evaluate_worker_edit.sh`

## 先備環境

server 內建議有：

- `node`
- `npm`
- `python3`
- `jq`
- `curl`
- `codex`

若你還要保留 Claude/router 備援路徑，再另外準備：

- `claude`
- `ccr`

Codex CLI 安裝範例：

```bash
npm install -g @openai/codex
```

如果也要備用 Claude/router：

```bash
npm install -g @anthropic-ai/claude-code
npm install -g @musistudio/claude-code-router
```

## 建議放置路徑

假設這份配置放在：

```bash
/srv/codex-claude-server-playbook
```

下面命令都以此為例。

## 開源模型服務假設

預設優先使用本機 Ollama OpenAI-compatible API：

- `http://127.0.0.1:11434/v1`

如果你用 LM Studio，可改成：

- `http://127.0.0.1:1234/v1`

若模型名稱不是 `qwen3:4b`，請自行用環境變數覆蓋：

```bash
export MODEL_NAME=qwen2.5-coder:7b
export OPENAI_BASE_URL=http://127.0.0.1:11434/v1
export OPENAI_API_KEY=dummy-key
```

如果你是 Ubuntu 22.04 image / container 內安裝，請先看：

- `ubuntu22.04/INSTALL.zh-TW.md`

## 啟動與驗證

### 1. 先測模型 endpoint

```bash
cd /srv/codex-claude-server-playbook
bash ./scripts/test_llm_endpoint.sh ollama
```

若是 Ubuntu 22.04 image 內從零安裝，可先跑：

```bash
cd /opt/codex-claude-server-playbook
bash ./scripts/setup_ubuntu2204_codex_master_worker.sh /opt/codex-claude-server-playbook
source ./profiles/qwen-small-safe.env.example
bash ./scripts/smoke_test_ubuntu2204_codex_master_worker.sh /opt/codex-claude-server-playbook
```

### 2. 啟動 Codex CLI

```bash
cd /srv/codex-claude-server-playbook
bash ./scripts/run_codex_openai_compat.sh
```

### 3. 用 guarded 模式做窄範圍規劃

```bash
cd /srv/codex-claude-server-playbook
bash ./scripts/run_codex_guarded.sh "Inspect src and identify the smallest safe next code task"
```

## Master Codex -> Worker Codex

### 自動拆 job 並執行 worker

```bash
cd /srv/codex-claude-server-playbook
bash ./scripts/orchestrate_codex_to_codex.sh "Inspect src and identify the smallest safe next code task" /srv/myrepo
```

### 單獨執行一個 worker job

```bash
cd /srv/codex-claude-server-playbook
bash ./scripts/worker_codex_cli.sh /path/to/job.json
```

## 如何降低 token overflow

1. master 只先建立 inventory，不直接讓模型掃整個資料夾。
2. planner 每個 job 預設最多只分到 3 個檔案。
3. worker prompt 明確禁止長 reasoning 與大範圍擴張。
4. worker overflow 後，orchestrator 會自動把多檔 job 再切成單檔 retry。
5. `summary.json` 會量化：
   - `avg_files_per_job`
   - `max_files_in_job`
   - `breadth_reduction_percent`
   - `workers_overflowed`
   - `overflow_retries`
   - `workers_need_replan`
   - `workers_false_success_blocked`

## Smoke Test

### 規劃 + orchestration 評估

```bash
cd /srv/codex-claude-server-playbook
bash ./scripts/evaluate_codex_orchestration.sh
```

### worker edit 評估

```bash
cd /srv/codex-claude-server-playbook
bash ./scripts/evaluate_codex_worker_edit.sh
```

### 舊版 Claude/router 評估

```bash
cd /srv/codex-claude-server-playbook
bash ./scripts/evaluate_orchestration.sh
bash ./scripts/evaluate_worker_edit.sh
```

## 給公司內部 follow 的建議順序

1. 先確認本機開源模型 API 可用。
2. 先跑 `evaluate_codex_orchestration.sh`，看拆 job 與 overflow 指標。
3. 再跑 `evaluate_codex_worker_edit.sh`，看 worker 是否真的能改檔與通過 pytest。
4. 最後才套到真實大型 repo。
5. 若 Codex-only 成效不夠，再對照 Claude/router 備援版。

## 風險提醒

1. master 和 worker 都改用開源模型後，成本更低，但規劃品質可能比商用大模型不穩。
2. 若 `workers_overflowed` 很高，先縮小 `ORCH_MAX_FILES_PER_JOB`，再換更大模型。
3. 若 `workers_need_replan` 很高，表示 master 拆 job 仍太粗。
4. 這套流程是降低單次 context 壓力，不保證所有 repo 都能一次成功。
