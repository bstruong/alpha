# Frontier Model Evaluation Scorecard
**Date:** 2026-10-07 03:11:21 UTC
**Hardware Target:** Metrotower (AMD Ryzen 7 9700X, RTX 3060 12GB, 32GB RAM, Samsung 990 Pro NVMe)

## 1. Hardware Throughput Matrix

| Context Size | TTFT (s) | Prefill (t/s) | Decode (t/s) | Peak RAM (MB) | Peak VRAM (MB) |
|--------------|----------|---------------|--------------|---------------|----------------|
| 2000 | 2.19 | 913.11 | 45.32 | 24904.74 | 6285 |
| 8000 | 6.332 | 1263.39 | 45.35 | 24969.94 | 6311 |
| 32000 | 24.003 | 1333.17 | 39.89 | 24967.61 | 6311 |
| 64000 | 30.059 | 2129.16 | 10.93 | 24956.03 | 6311 |

## 2. Cognitive Spec Trap Pass/Fail Rates

| Test | Description | Result |
|------|-------------|--------|
| **Test A** | Precision Guard (decimal.Decimal vs float) | ❌ FAIL |
| **Test B** | Multi-File Dependency Consistency | ❌ FAIL |
| **Test C** | Reasoning Scratchpad Ceiling (≤ 5 bullets) | ❌ FAIL |

## 3. Two-Model Pipeline Latency & Handoff Quality Score

- **Model Swap Latency (100B+ -> 35B):** 0.0 seconds
- **Worker Execution Time:** 10.674 seconds
- **Worker Execution Success (Under 15s):** ✅ PASS

### Handoff Quality Score
Overall Pipeline Status: **✅ HEALTHY**
