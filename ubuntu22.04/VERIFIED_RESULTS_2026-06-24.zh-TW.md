# Ubuntu 22.04 + Codex + 開源模型實測結果

測試日期：2026-06-24

## 測試環境

- Host OS: Windows
- Docker Engine: `20.10.23`
- Docker Compose: `v2.15.1`
- Container base image: `ubuntu:22.04`
- Container Codex CLI: `codex-cli 0.142.0`
- Node.js: `v20.20.2`
- npm: `10.8.2`

## Host 可用模型

透過 container 內呼叫：

```bash
curl http://host.docker.internal:11434/v1/models
```

實際看得到：

- `gemma3:4b`
- `qwen3:4b`
- `qwen2.5-coder:3b`

## 已驗證成功的部分

### 1. Ubuntu 22.04 image 可成功 build

已成功 build：

- image name: `codex-master-worker-oss:ubuntu22.04`

### 2. Container 內 Codex 可正常啟動

已驗證：

- `codex --version`
- `node -v`
- `npm -v`

### 3. Container 可連到 host 的開源模型服務

已驗證 endpoint：

- `http://host.docker.internal:11434/v1/models`

### 4. Master Codex 規劃模式可運作

在 `examples/hello-python` 上，planning-only orchestration 已成功：

- `planner_exit = 0`
- `planner_parse_ok = true`
- `workers_overflowed = 0`
- `max_files_in_job = 2`

這表示：

- 小模型做 inventory + 小 job 拆解是可行的
- 以低上下文規劃為主的流程可以跑通

### 5. Managed single-file child edit 已驗證可行

在 Ubuntu 22.04 container 內，使用：

- `master codex`
- `managed single-file child codex`
- 本機開源模型 `qwen2.5-coder:3b`

已成功做到：

- master 規劃單檔 edit job
- child 回傳最終檔案內容
- wrapper 安全落地到目標檔案
- `pytest -q` 通過
- `workers_overflowed = 0`

## 已驗證失敗或有限制的部分

### 1. Direct worker Codex 會口頭回報 SUCCESS，但沒有真的改檔

在 `qwen3:4b` 與 `qwen2.5-coder:3b` 兩個模型上，都出現：

- worker 回覆：
  - `STATUS: SUCCESS`
  - `FILES: tests/test_placeholder.py`
  - `TESTS: pytest -q passed`
- 但實際檔案沒有變
- verification 會抓到：
  - `actual_changed_count = 0`
  - `verification_note = claimed success without verified file change`

這代表：

- 這些小模型在目前 direct tool-based Codex worker 模式下，較像「能理解任務並生成答案」
- 但不穩定地執行真正的檔案編輯動作

### 2. OpenAI-compatible 路徑會先嘗試 WebSocket，Ollama 回 405

Codex exec log 看到：

- `failed to connect to websocket`
- `405 Method Not Allowed`
- 然後 fallback 到 HTTPS transport

這不會阻止規劃，但可能讓執行體驗和工具穩定性下降。

## 目前最誠實的結論

### 可成立的說法

1. Ubuntu 22.04 container 內的 Codex 已可連上 host 的開源模型。
2. `master codex -> child codex` 的規劃與任務拆解可用。
3. 低上下文設計確實能降低 overflow 風險。
4. 對小 repo 做 inspect / planning 類工作是可行的。
5. `qwen2.5-coder:3b` 已可走 `managed single-file edit` 並通過實測。

### 目前不能宣稱已完成的說法

1. 不能宣稱 `qwen3:4b` 已能穩定擔任 direct tool-based child edit worker。
2. 不能宣稱所有小模型都已能穩定擔任多檔 child edit worker。
3. 不能宣稱目前這組小模型已能無限制地順暢自動修檔。

## 目前建議的使用分層

### 建議 A：開源模型只做 master planner

適合：

- 大 repo 避免 overflow
- 先拆小 job
- 先做 inventory、triage、inspect

### 建議 B：child codex 先限定 inspection-only

適合：

- 摘要
- 找最小下一步
- 指定檔案清單
- 產出局部修改建議

### 建議 C：若需要真實改檔，優先用 managed single-file worker

適合：

- 單檔 edit
- 小範圍受控重寫
- 需要保留 verification gate 的情境

目前已驗證可用模型：

- `qwen2.5-coder:3b`

### 建議 D：若一定要做多檔或更自由的自動改檔

目前較穩妥的方向：

1. 改用更強的 code model
2. 或把 child worker 換成較成熟的實作端
3. 或保留 verification gate，讓 master 遇到假成功時重新規劃

## 推薦模型角色

請搭配閱讀：

- `ubuntu22.04/MODEL_ROLE_MATRIX_2026-06-24.zh-TW.md`

目前最建議：

- `master codex = qwen2.5-coder:3b`
- `child codex = managed single-file edit` 或 inspection-first

目前不建議：

- `gemma3:4b` 用於這套需要 tools 的 Codex orchestration

## 這份實測對安裝指引的影響

安裝指引仍然有效，但要加上這句判斷：

- `planning verified`
- `managed single-file editing verified on qwen2.5-coder:3b`
- `direct child tool-editing still not reliable on small local models`

這樣公司內部 follow 的人就不會把目前能力誤判成已可全自動改碼。
