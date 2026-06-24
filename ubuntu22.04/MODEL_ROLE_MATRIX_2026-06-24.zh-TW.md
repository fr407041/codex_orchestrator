# 開源模型角色矩陣

資料日期：2026-06-24

## 實測模型

- `qwen3:4b`
- `qwen2.5-coder:3b`
- `gemma3:4b`

## 角色建議總表

| 模型 | Master planner | Child inspect worker | Child direct edit worker | Child managed single-file edit worker | 結論 |
| --- | --- | --- | --- | --- | --- |
| `qwen3:4b` | 可用 | 可用 | 不可靠 | 可用，但 end-to-end 較不穩 | 適合規劃與小範圍 managed edit 實驗 |
| `qwen2.5-coder:3b` | 可用 | 可用 | 不可靠 | 已驗證可用 | 目前最推薦的 end-to-end 開源配置 |
| `gemma3:4b` | 不建議 | 不建議 | 不可用 | 不可用 | 在目前 Ollama 路徑下不適合這套 Codex flow |

## 實測重點

### `qwen3:4b`

- 規劃可成功產出可解析 JSON
- `workers_overflowed = 0`
- child worker 會理解 edit 任務
- 但 verification 顯示沒有真實檔案變更

建議角色：

- `master codex`
- `child codex` 的 inspect-only / triage-only 工作
- `managed single-file child codex` 可做受控單檔改寫，但比 `qwen2.5-coder:3b` 更不穩

### `qwen2.5-coder:3b`

- 對 worker 回傳格式理解良好
- 可以回 `STATUS: SUCCESS`
- 但 verification 顯示：
  - `actual_changed_count = 0`
  - 屬於「口頭成功但沒改檔」

建議角色：

- 可作 `master codex`
- 可作 `child codex` inspect-only / suggestion-only 工作
- 已驗證可作 `managed single-file child edit worker`

### `gemma3:4b`

- 在目前 Codex + Ollama OpenAI-compatible 路徑下，log 出現：
  - `does not support tools`
- 所以不適合這套 Codex worker orchestration

建議角色：

- 不要用在這套需要 Codex tools / file edit 的 flow

## 推薦預設

### 推薦 1：目前最穩的 end-to-end 配置

- `master codex = qwen2.5-coder:3b`
- `child codex = qwen2.5-coder:3b`
- child edit 模式使用 `managed single-file worker`
- 適合：
  - inventory
  - inspect
  - summarize
  - identify smallest next task
  - 單檔受控改寫

### 推薦 2：較穩的低上下文規劃配置

- `master codex = qwen3:4b`
- `child codex = inspect-only` 或 `managed single-file worker`
- 適合先做 planning，再保守地派單檔任務

### 推薦 3：若任務一定要 edit

請保留：

- `require_change = true`
- before/after hash verification
- test command verification
- master replan on false success

而且不要宣稱 direct tool-based child 已可穩定自動改檔。

## 目前最符合目標的說法

這套 Ubuntu 22.04 image 內的 Codex orchestration：

1. 已可用開源模型建立 `master codex -> child codex`
2. 已能降低 overflow 風險並順利做 planning
3. 已能讓 child 做 inspect / triage 類任務
4. `qwen2.5-coder:3b` 已可走 `managed single-file edit`
5. 但 direct tool-based child edit 在小模型下仍不建議當主路徑
