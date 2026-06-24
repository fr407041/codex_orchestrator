# Codex Orchestrator

這份 flow 假設你已經在 server、WSL、或 container 內準備好：

- `codex`
- `node`
- `npm`
- `python3`
- `jq`
- `curl`
- 一個已經可用的 OpenAI-compatible 開源模型服務

這份文件故意不放 `codex` 安裝流程，也不放下載或安裝開源模型的流程。重點只放在：

- 自動偵測已安裝好的本機模型
- `master codex -> worker codex CLI` 拆任務
- 避免 token overflow
- 多輪驗證是否穩定

## 你會得到什麼

- `scripts/detect_openai_compat_model.sh`
- `scripts/resolve_model_env.sh`
- `scripts/test_llm_endpoint.sh`
- `scripts/run_codex_openai_compat.sh`
- `scripts/run_codex_guarded.sh`
- `scripts/orchestrate_codex_to_codex.sh`
- `scripts/worker_codex_cli.sh`
- `scripts/worker_codex_managed_single_file.sh`
- `scripts/evaluate_codex_orchestration.sh`
- `scripts/evaluate_codex_worker_edit.sh`
- `scripts/evaluate_codex_managed_orchestration.sh`
- `scripts/evaluate_codex_managed_worker_edit.sh`
- `scripts/evaluate_codex_multi_round.sh`
- `prompts/master_codex_bootstrap.zh-TW.md`
- `profiles/qwen-small-safe.env.example`
- `examples/hello-python/`

## 核心原則

1. 不指定固定模型名稱，先從已安裝模型自動挑一個可用模型。
2. `master codex` 只拿小 inventory 與小範圍規劃。
3. `worker codex` 每次只處理極少數檔案。
4. 一旦任務明確點名單檔，就直接走 deterministic single-file mode。
5. worker 若出現 context 壓力，要能回報 `OVERFLOW_DETECTED`。
6. worker 若沒有真的改到檔案，不算成功。

## 預設支援的端點

- `http://127.0.0.1:11434/v1`
- `http://host.docker.internal:11434/v1`
- `http://127.0.0.1:1234/v1`
- `http://host.docker.internal:1234/v1`

腳本會優先偵測可用端點，再從 `/v1/models` 回傳結果中挑一個較適合 coding 的模型。

## 快速開始

先確認端點可用：

```bash
bash ./scripts/test_llm_endpoint.sh auto
```

讓環境變數自動完成：

```bash
source ./scripts/resolve_model_env.sh
echo "$OPENAI_BASE_URL"
echo "$MODEL_NAME"
```

啟動一般 Codex：

```bash
bash ./scripts/run_codex_openai_compat.sh
```

啟動 guarded 規劃模式：

```bash
bash ./scripts/run_codex_guarded.sh "Inspect src and identify the smallest safe next code task"
```

## Master -> Worker

```bash
bash ./scripts/orchestrate_codex_to_codex.sh \
  "Inspect the repo, identify the smallest safe next code task, and avoid broad reads." \
  /path/to/repo
```

如果任務直接指定單一檔案，例如：

```bash
bash ./scripts/orchestrate_codex_to_codex.sh \
  "Edit tests/test_placeholder.py so it contains a deterministic assertion assert 1 + 1 == 2 and keep the file minimal." \
  ./examples/hello-python
```

則會優先走單檔 managed worker。

## 驗證

小型 repo 驗證：

```bash
bash ./scripts/evaluate_codex_orchestration.sh
bash ./scripts/evaluate_codex_worker_edit.sh
```

多輪驗證：

```bash
bash ./scripts/evaluate_codex_multi_round.sh 3
```

觀察指標：

- `planner_parse_ok`
- `workers_failed`
- `workers_overflowed`
- `workers_need_replan`
- `workers_false_success_blocked`
- `workers_with_verified_changes`

## 最新實測結果

在本機 Docker build 的 Ubuntu 22.04 image 內，透過 `host.docker.internal:11434/v1` 連到已安裝的 host 模型服務，腳本自動選到：

- `MODEL_NAME=qwen2.5-coder:3b`

最近一次 3 輪驗證結果：

- `planner_parse_ok=True`
- `workers_failed=0`
- `workers_overflowed=0`
- `workers_need_replan=0`
- `workers_false_success_blocked=0`
- `workers_with_verified_changes=1` 每輪皆成立

## 推薦給公司內部 follow 的提示

- 不要先讀整個 repo
- 先列 inventory，再挑小範圍
- 每個 worker job 最多 1 到 2 個檔案
- 遇到 overflow 就重切，不要硬做
- 沒有 verified change 不算完成

對應 prompt 在：

- `prompts/master_codex_bootstrap.zh-TW.md`

## 安全說明

- repository 只放 placeholder key，例如 `dummy-key`
- 發布前請再檢查 `SAFE_PUBLISHING.md`
