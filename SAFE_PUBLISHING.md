# Safe Publishing Notes

這份 server playbook 已排除：

- Docker image 建置檔
- 歷史 orchestrator 執行輸出
- `.pytest_cache`
- `__pycache__`
- 與本次用途無關的舊 deliverables

仍保留的測試 placeholder：

- `local-test-key`
- `dummy-key`
- `ollama`

這些不是實際 secret，只是範例配置值。

若要再更保守，可把它們改成：

- `CHANGE_ME`
- `PLACEHOLDER_ONLY`
