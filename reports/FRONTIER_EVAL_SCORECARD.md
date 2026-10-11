# Frontier Model Evaluation Scorecard
**Date:** 2026-10-11 02:55:55 UTC
**Hardware Target:** Workstation (AMD Ryzen 7 9700X, RTX 3060 12GB, 32GB RAM, Samsung 990 Pro NVMe)
**Harness:** v3+ — independent modules; temp 0 / seed 12345 / no prompt cache; slot erase; oracles A/B; soft Test C; primary telemetry 2k/8k; Test C named deliverables+retry; planner token cap
**Modules last updated:** telemetry=2026-10-11T02:53:28.431417+00:00 · spec_traps=2026-10-11T02:55:55.847652+00:00 · pipeline=2026-10-10T18:17:23.472800+00:00

## 1. Hardware Throughput Matrix

| Context Size | TTFT (s) | Prefill (t/s) | Decode (t/s) | Peak RAM (MB) | Peak VRAM (MB) |
|--------------|----------|---------------|--------------|---------------|----------------|
| 2000* | 1.462 | 1367.59 | 50.27 | 23206.45 | 10699 |
| 8000* | 5.179 | 1544.74 | 48.35 | 23279.67 | 10719 |
| 32000† | 21.558 | 1484.36 | 41.67 | 23505.18 | 10719 |
| 64000† | 30.054 | 2129.48 | 1.78 | 23476.97 | 10719 |

\* Primary regression metrics: 2k/8k. † 32k/64k decode is NVMe-bound (secondary signal only).

## 2. Cognitive Spec Trap Pass/Fail Rates

| Test | Description | Result |
|------|-------------|--------|
| **Test A** | Precision Guard (decimal.Decimal vs float) | ✅ PASS |
| **Test B** | Multi-File Dependency Consistency | ✅ PASS |
| **Test C** | Code deliverable (scratchpad ≤ 5 bullets is a soft flag) | ✅ PASS |

## 3. Two-Model Pipeline Latency & Handoff Quality Score

- **Model Swap Latency (100B+ -> 35B):** 10.917 seconds
- **Worker Execution Time:** 11.295 seconds
- **Worker Execution Success (Under 15s):** ✅ PASS
- **Failure Reason:** none
- **Planner / Phase 1.1 chars:** 444 / 444

- **Planner metrics:** {'wall_sec': 14.191, 'prompt_tokens': 76, 'completion_tokens': 494, 'reasoning_tokens': 0, 'requests': 1}
- **Worker metrics:** {'wall_sec': 11.295, 'prompt_tokens': 112, 'completion_tokens': 500, 'reasoning_tokens': None, 'prompt_per_second': 190.92102347305797, 'predicted_per_second': 46.64264554842217}

### Handoff Quality Score
Overall Pipeline Status: **✅ HEALTHY**

### Notes
- Run modules independently; each merges into `reports/frontier_full_eval.json` without wiping other modules.
- Per-trap metrics and response previews live in the JSON / `reports/moduleN_*.json`.
- Flash-Next uses mmap (required on 32GB); Tier-1 worker uses mlock/cpu-moe when memlock allows.
