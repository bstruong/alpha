# Handoff: Qwen 3.8 Flash benchmark

**Read first:** [`QWEN38_FLASH_BENCHMARK_REPORT.md`](QWEN38_FLASH_BENCHMARK_REPORT.md)

## Status (2026-10-07)

| Item | State |
|------|--------|
| Engine | qwen4exp `llama-server`; **stopped** after last run |
| Latest Flash run | **M1 + M2 only** — A/B/C **PASS**; primary decode **2.13 / 1.01** t/s (2k/8k) |
| Module 3 | Not refreshed; scorecard §3 may show prior HEALTHY + expensive planner |
| Verdict | Flash = specialist reasoner; Tier-1 = daily coding; 32GB mmap ceiling |

## Artifacts

- Scorecard: [`FRONTIER_EVAL_SCORECARD.md`](FRONTIER_EVAL_SCORECARD.md)
- JSON: [`frontier_full_eval.json`](frontier_full_eval.json), [`module1_telemetry.json`](module1_telemetry.json), [`module2_spec_traps.json`](module2_spec_traps.json)
- Stack brief: [`STACK_TECHNOLOGY_BRIEF.md`](STACK_TECHNOLOGY_BRIEF.md)
- Re-run notes: [`NEXT_BENCHMARK_RUN.md`](NEXT_BENCHMARK_RUN.md)
- Host logs (historical only): `/tmp/frontier_m1_flash.log`, `/tmp/frontier_m2_flash.log`, `/tmp/frontier_benchmark_v3.log`

## Runners

- `scripts/run_module1_telemetry.py`
- `scripts/run_module2_spec_traps.py`
- `scripts/run_module3_pipeline.py`
- `scripts/run_full_benchmark.py` (optional chain)
