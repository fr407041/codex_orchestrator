# Codex Orchestrator

這份 playbook 以 `master codex -> worker codex CLI` 為主，目標是讓較小的開源 LLM 也能先拆任務、再分批執行，降低單次讀太多檔案而造成 token overflow 的機率。

這次公開版本刻意聚焦在 server 內直接執行的流程：

- `master codex` 負責盤點 scope、規劃小 job、偵測 overflow 與 replan
- `worker codex CLI` 負責只看指定少量檔案並回傳結果
- 預設接 OpenAI-compatible endpoint，例如 Ollama 或 LM Studio

這個 repository 不把 Docker image、benchmark 輸出、暫存結果、`.pytest_cache`、`__pycache__` 當成主要發布內容。

## 核心檔案

- `scripts/orchestrate_codex_to_codex.sh`
- `scripts/worker_codex_cli.sh`
- `scripts/worker_codex_managed_single_file.sh`
- `scripts/run_codex_guarded.sh`
- `scripts/run_codex_openai_compat.sh`
- `scripts/run_codex_oss.sh`
- `scripts/test_llm_endpoint.sh`
- `scripts/detect_openai_compat_model.sh`
- `scripts/resolve_model_env.sh`
- `prompts/master_codex_bootstrap.zh-TW.md`
- `profiles/qwen-small-safe.env.example`
- `codex-config/config.toml.example`
- `codex-config/config.oss.example.toml`
- `examples/hello-python/`

## 適用情境

當你直接讓單一 Codex CLI 讀整個 repo，常遇到這類問題時，這套流程比較有幫助：

- output token 要求過大
- 小模型先噴長 reasoning，真正可用內容很少
- 單次 scope 太廣，worker 還沒開始做事就先爆 context
- 子代理也因為被派太大的 job 而一起 overflow

## 流程概念

1. `master codex` 先建立檔案 inventory，但只抽樣小範圍給 planner。
2. planner 最多只切出少量 job，每個 job 最多碰少數檔案。
3. 若任務明確指定單一檔案，會走 deterministic single-file managed edit，避免又被自由規劃擴大。
4. `worker codex CLI` 只處理自己的 job。
5. 若 worker 回報 `OVERFLOW_DETECTED`，master 會把 job 再拆細。
6. 若 worker 沒有真正改到檔案卻聲稱成功，會被標成 false success block，避免主代理誤判完成。

## 先決條件

server 端請先有：

- `node`
- `npm`
- `python3`
- `jq`
- `curl`
- `codex`

安裝 Codex CLI：

```bash
npm install -g @openai/codex
```

## 模型端點

支援 OpenAI-compatible API，常見例子：

- Ollama: `http://127.0.0.1:11434/v1`
- LM Studio: `http://127.0.0.1:1234/v1`

如果不想手動指定模型，可讓腳本自動偵測：

```bash
bash ./scripts/test_llm_endpoint.sh auto
source ./scripts/resolve_model_env.sh auto
echo "$OPENAI_BASE_URL"
echo "$MODEL_NAME"
```

## 快速開始

先測試 endpoint：

```bash
bash ./scripts/test_llm_endpoint.sh auto
```

啟動互動式 Codex CLI：

```bash
bash ./scripts/run_codex_openai_compat.sh
```

執行 guarded 模式：

```bash
bash ./scripts/run_codex_guarded.sh "Inspect src and identify the smallest safe next code task"
```

讓 master 派 worker：

```bash
bash ./scripts/orchestrate_codex_to_codex.sh \
  "Inspect the repo, identify the smallest safe next code task, and avoid broad reads." \
  /path/to/repo
```

## 驗證方式

小型 repo 驗證：

```bash
bash ./scripts/evaluate_codex_orchestration.sh
bash ./scripts/evaluate_codex_worker_edit.sh
```

強制單檔 managed edit 驗證：

```bash
bash ./scripts/evaluate_codex_managed_orchestration.sh
bash ./scripts/evaluate_codex_managed_worker_edit.sh
```

多輪穩定性驗證：

```bash
bash ./scripts/evaluate_codex_multi_round.sh 3
```

重點觀察 `summary.json` 內這些欄位：

- `workers_overflowed`
- `workers_failed`
- `workers_need_replan`
- `workers_false_success_blocked`
- `workers_with_verified_changes`
- `max_files_in_job`

## 參考策略

如果你要把這套思路交給公司內部 Codex follow，可先要求它遵守這幾條：

- 先縮 scope，再規劃
- 每個 worker job 最多只看極少數檔案
- 先做 investigation job，再做 edit job
- 遇到 overflow 就重切 job，不要硬撐
- 沒有 verified file change 不算成功

對應的啟動提示可直接參考：

- `prompts/master_codex_bootstrap.zh-TW.md`

## 安全說明

- 這份公開版本只放 placeholder key，例如 `dummy-key`
- 不應提交真實 API key、帳密、session、token
- 發布前可再檢查 `SAFE_PUBLISHING.md`
