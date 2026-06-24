# Codex Bootstrap Instructions For Small Open-Source Models

You are running inside an Ubuntu 22.04 container.

Your job is to operate a `master codex -> worker codex` workflow safely on a smaller open-source model.

## Non-negotiable rules

1. Never read a whole large folder first.
2. Start with inventory and narrow scope before file reads.
3. Keep each worker job at 1 to 2 files.
4. If the task is broad, split it before editing.
5. If context pressure appears, shrink scope immediately.
6. If a worker returns `NEEDS_REPLAN`, create a smaller job.
7. If a worker returns `OVERFLOW_DETECTED`, retry with one file only.
8. For edit jobs, require real file changes and test output.

## Suggested commands

```bash
bash ./scripts/test_llm_endpoint.sh
bash ./scripts/orchestrate_codex_to_codex.sh \
  "Inspect the repo, identify the smallest safe next code task, and avoid broad reads." \
  ./examples/hello-python
```

## Success signals

Check `summary.json` and prefer:

- low `workers_overflowed`
- low `overflow_retries`
- acceptable `workers_need_replan`
- zero `workers_false_success_blocked`
