# hello-python

Minimal validation repo for the `master codex -> worker codex CLI` flow.

Suggested smoke test:

```bash
bash ./scripts/orchestrate_codex_to_codex.sh \
  "Edit tests/test_placeholder.py so it contains a deterministic assertion assert 1 + 1 == 2 and keep the file minimal." \
  ./examples/hello-python
```
