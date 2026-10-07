# Frontier Model Evaluation Scorecard
**Date:** 2026-10-07 22:20:02 UTC
**Hardware Target:** Workstation (AMD Ryzen 7 9700X, RTX 3060 12GB, 32GB RAM, Samsung 990 Pro NVMe)
**Harness:** v3+ — independent modules; temp 0 / seed 12345 / no prompt cache; slot erase; oracles A/B; soft Test C; primary telemetry 2k/8k; Test C named deliverables+retry; planner token cap
**Modules last updated:** telemetry=2026-10-07T21:41:04.552767+00:00 · spec_traps=2026-10-07T22:15:26.958314+00:00 · pipeline=never

## 1. Hardware Throughput Matrix

| Context Size | TTFT (s) | Prefill (t/s) | Decode (t/s) | Peak RAM (MB) | Peak VRAM (MB) |
|--------------|----------|---------------|--------------|---------------|----------------|
| 2000* | 14.267 | 140.19 | 2.13 | 3772.41 | 7327 |
| 8000* | 30.035 | 266.36 | 1.01 | 3540.57 | 7331 |
| 32000† | 30.073 | 1064.09 | 0.0 | 3388.3 | 7333 |
| 64000† | 30.136 | 2123.73 | 0.0 | 3307.0 | 7333 |

\* Primary regression metrics: 2k/8k. † 32k/64k decode is NVMe-bound (secondary signal only).

## 2. Cognitive Spec Trap Pass/Fail Rates

| Test | Description | Result |
|------|-------------|--------|
| **Test A** | Precision Guard (decimal.Decimal vs float) | ✅ PASS |
| **Test B** | Multi-File Dependency Consistency | ✅ PASS |
| **Test C** | Code deliverable (scratchpad ≤ 5 bullets is a soft flag) | ✅ PASS |

## 3. Two-Model Pipeline Latency & Handoff Quality Score

_Stale — retained from a prior Module 3 run; not refreshed this session (header: pipeline=never). Re-run `python3 scripts/run_module3_pipeline.py` to update._

- **Model Swap Latency (100B+ -> 35B):** 11.468 seconds
- **Worker Execution Time:** 11.433 seconds
- **Worker Execution Success (Under 15s):** ✅ PASS
- **Failure Reason:** none
- **Planner / Phase 1.1 chars:** 1913 / 672

- **Planner metrics:** {'wall_sec': 1366.308, 'prompt_tokens': 327, 'completion_tokens': 5000, 'reasoning_tokens': 0, 'requests': 2}
- **Worker metrics:** {'wall_sec': 11.433, 'prompt_tokens': 181, 'completion_tokens': 500, 'reasoning_tokens': None, 'prompt_per_second': 262.347736852175, 'predicted_per_second': 46.466519196771735}

### Handoff Quality Score
Overall Pipeline Status: **✅ HEALTHY**

### Notes
- Run modules independently; each merges into `reports/frontier_full_eval.json` without wiping other modules.
- Per-trap metrics and response previews live in the JSON / `reports/moduleN_*.json`.
- Flash-Next uses mmap (required on 32GB); Tier-1 worker uses mlock/cpu-moe when memlock allows.
