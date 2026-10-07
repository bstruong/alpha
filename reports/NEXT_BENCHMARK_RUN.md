# Next Benchmark Run

Canonical results and verdict: [`QWEN38_FLASH_BENCHMARK_REPORT.md`](QWEN38_FLASH_BENCHMARK_REPORT.md).  
Latest scorecard: [`FRONTIER_EVAL_SCORECARD.md`](FRONTIER_EVAL_SCORECARD.md).

**As of 2026-10-07:** Flash **Module 1 + Module 2** already completed (A/B/C PASS; primary decode 2.13 / 1.01 t/s). **Module 3 was not refreshed** in that session. Do **not** start the engine unless you intend a new burn (~5–15 min M1, ~30+ min M2, planner-heavy M3).

## Run (when ready)

```bash
cd /home/user/Projects/berserker

engine/bin/llama-up.sh router qwen3.8-flash --force

PYTHONUNBUFFERED=1 python3 scripts/run_module1_telemetry.py
PYTHONUNBUFFERED=1 python3 scripts/run_module2_spec_traps.py
PYTHONUNBUFFERED=1 python3 scripts/run_module3_pipeline.py   # needs router (Flash → qwen36-coder)

# optional chain:
# PYTHONUNBUFFERED=1 python3 scripts/run_full_benchmark.py

engine/bin/llama-down.sh
```

| Module | Script | Needs |
|--------|--------|-------|
| 1 Telemetry | `scripts/run_module1_telemetry.py` | Flash on :8080 |
| 2 Spec traps | `scripts/run_module2_spec_traps.py` | Flash on :8080 |
| 3 Pipeline | `scripts/run_module3_pipeline.py` | **Router** Flash + `qwen36-coder` |

Outputs merge into `reports/frontier_full_eval.json` and regenerate the scorecard. Primary regression metrics: **2k/8k** decode; 32k/64k are NVMe-bound secondary only.

## Prep already in tree

- Repro knobs + slot erase (`slot-save-path` in `engine/models.ini`)
- Canonical id `qwen3.8-flash`; Pi `contextWindow` 69632; `spec-type = none`
- Oracles A/B; Test C named deliverables + retry; planner `max_tokens=700`
- Optional: `sudo engine/bin/setup-memlock.sh --install` for real Tier-1 mlock (needs password)

Stack deep-dive: [`STACK_TECHNOLOGY_BRIEF.md`](STACK_TECHNOLOGY_BRIEF.md).
