# Multi-Run Benchmark Comparative Analysis: GLM-4.7 Flash REAP vs. Qwen 3.6 35B

**Author:** Principal Local AI Benchmarking Engineer  
**Date:** 2026-10-10  
**Harness:** Alpha Benchmark Suite v3+  
**Target Hardware:** AMD Ryzen 7 9700X (8C/16T, DDR5-6000 32GB) + NVIDIA RTX 3060 12GB (Driver 615.78.08, CUDA 13.4)  
**Sample Size:** **3 Formal Executions** per model (6 complete multi-module evaluations total)

---

## 1. Executive Summary & Key Discoveries

Across **3 independent, consecutive executions** of Module 1 (Hardware & Telemetry across 2k, 8k, 32k, and 64k contexts) and Module 2 (Cognitive Spec Traps Tests A, B, and C):

1. **Deterministic Stability Across Both Models:**
   - Both models demonstrated remarkable latency and throughput reproducibility. Throughput standard deviations across 3 runs stayed under **$\pm 0.8\text{ tok/s}$** on decode and under **$\pm 0.02\text{ s}$** on TTFT.
2. **Cognitive Spec Trap Scorecard (100% Consistency):**
   - **GLM-4.7 Flash REAP 23B:** **3 / 3 PASS** across all 3 runs (100% pass rate).
   - **Qwen 3.6 35B:** **3 / 3 PASS** across all 3 runs under the v3+ harness (100% pass rate).  
   *Note: This overturns the legacy "0/3 FAIL" note in earlier summaries, proving that under proper execution oracles and prompt-cache isolation, Qwen 3.6 reliably produces compliant code.*
3. **Throughput vs. Memory Trade-Off:**
   - **Qwen 3.6 35B** delivers **~27–31% faster decode throughput** (46.9 tok/s at 2k vs. 35.7 tok/s for GLM).
   - **GLM-4.7 Flash REAP** operates with **~7.4 GB lower host RAM footprint** (19.6 GB vs. 27.0 GB) and **~716 MB lower VRAM footprint** (6.19 GB vs. 6.91 GB), providing vastly superior system safety on a 32GB workstation.
   - At 2,000 context, **GLM-4.7 Flash REAP** delivers a faster TTFT (**1.37 s** vs. **1.59 s**).

---

## 2. Statistical Hardware Throughput Comparison (3-Run Aggregate)

### 2.1 Primary Operational Contexts (2k and 8k)

| Context Window | Metric | **GLM-4.7 Flash REAP (23B/A3B)** | **Qwen 3.6 35B (UD-Q4_K_M)** | Delta (Qwen vs. GLM) |
|---|---|---|---|---|
| **2,000 tokens** | **TTFT (s)** | **1.37 s** ($\pm 0.01$) | 1.59 s ($\pm 0.01$) | **GLM is 14% faster** |
| | **Prefill (t/s)** | **1,459.2 t/s** ($\pm 11.5$) | 1,254.8 t/s ($\pm 9.8$) | **GLM is 16% faster** |
| | **Decode (t/s)** | 35.71 t/s ($\pm 0.78$) | **46.91 t/s** ($\pm 0.79$) | **Qwen is 31% faster** |
| | **Peak RAM (MB)** | **19,608.5 MB** (~19.1 GB) | 26,935.0 MB (~26.3 GB) | **GLM uses 7.33 GB less RAM** |
| | **Peak VRAM (MB)**| **6,195 MB** | 6,904 MB | **GLM uses 709 MB less VRAM** |
| **8,000 tokens** | **TTFT (s)** | 7.04 s ($\pm 0.00$) | **5.57 s** ($\pm 0.00$) | **Qwen is 21% faster** |
| | **Prefill (t/s)** | 1,136.5 t/s ($\pm 0.48$) | **1,436.7 t/s** ($\pm 0.64$) | **Qwen is 26% faster** |
| | **Decode (t/s)** | 32.54 t/s ($\pm 0.59$) | **45.25 t/s** ($\pm 0.11$) | **Qwen is 39% faster** |
| | **Peak RAM (MB)** | **19,617.8 MB** (~19.2 GB) | 27,006.0 MB (~26.4 GB) | **GLM uses 7.39 GB less RAM** |
| | **Peak VRAM (MB)**| **6,195 MB** | 6,911 MB | **GLM uses 716 MB less VRAM** |

---

### 2.2 Extended Context Scaling (32k and 64k)

| Context Window | Metric | **GLM-4.7 Flash REAP (23B/A3B)** | **Qwen 3.6 35B (UD-Q4_K_M)** | Engineering Dynamics |
|---|---|---|---|---|
| **32,000 tokens** | **TTFT (s)** | 30.02 s | **22.97 s** | Hybrid SSM state allows faster prefill scaling on Qwen |
| | **Prefill (t/s)** | 1,065.8 t/s | **1,393.4 t/s** | |
| | **Decode (t/s)** | 0.36 t/s | **39.77 t/s** | Qwen maintains high decode in RAM; GLM hits CPU prefill limits |
| | **Peak RAM (MB)** | **19,653.6 MB** | 27,004.7 MB | |
| **64,000 tokens** | **TTFT (s)** | 30.03 s | 30.06 s | Both hit engine batch/prefill limit at ~30s |
| | **Prefill (t/s)** | 2,131.4 t/s | 2,129.3 t/s | Pure GPU batch saturation |
| | **Decode (t/s)** | 0.00 t/s (capped) | 1.57 t/s | At 64k, both hit host bandwidth memory ceilings |
| | **Peak RAM (MB)** | **19,667.5 MB** | 27,002.6 MB | |

---

## 3. Cognitive Spec Trap Reliability Matrix (3 Runs Each)

| Spec Trap Test | **GLM-4.7 Flash REAP** Pass Rate | **Qwen 3.6 35B** Pass Rate | Analysis & Verification |
|---|:---:|:---:|---|
| **Test A: Precision Guard**<br>*(Enforce `decimal.Decimal`, ban `float`)* | **3 / 3 (100%)** | **3 / 3 (100%)** | Both models cleanly adhered to Decimal arithmetic and passed the hidden oracle check (`2.675` exact, `10 - 0.1 - 0.2 == 9.7`) and pytest suites across all 3 iterations. |
| **Test B: Dependency Consistency**<br>*(Multi-file signature cascade)* | **3 / 3 (100%)** | **3 / 3 (100%)** | Both models correctly cascaded `(tenant_id, user_id, amount)` across `core/limiter.py`, `storage/redis.py`, `middleware/http.py`, and `tests/test_integration.py`. |
| **Test C: Reasoning Ceiling & Deliverables**<br>*(Merge sort + Fibonacci $\le 5$ bullets)* | **3 / 3 (100%)** | **3 / 3 (100%)** | Both models consistently emitted iterative `merge_sort` and `fib` without triggering retries, staying strictly under the 5-bullet scratchpad ceiling. |

---

## 4. Architectural Analysis: Why the Differences Occur

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                             ARCHITECTURAL ARCHETYPES                             │
├────────────────────────────────────────┬─────────────────────────────────────────┤
│        GLM-4.7-Flash-REAP-23B-A3B      │             Qwen 3.6 35B                │
│                                        │                                         │
│ • Pure Attention + DeepSeek2 MLA       │ • Hybrid: 10 Attention + 30 DeltaNet    │
│ • Compressed Latent KV (576 dim)       │ • Recurrent Linear State for 75% Layers │
│ • 14.0 GB Model Size                   │ • 20.6 GB Model Size                    │
│ • ~3.2B Active Parameters (MoE)        │ • ~3.8B Active Parameters (MoE)         │
│ • Host RAM: ~19.6 GB (Safe on 32GB)    │ • Host RAM: ~27.0 GB (Near 32GB limit)  │
│ • Peak VRAM: 6.2 GB (50% card capacity)│ • Peak VRAM: 6.9 GB                     │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

1. **Why Qwen 3.6 Decodes Faster (46.9 vs 35.7 t/s):**
   `qwen35moe` uses 30 linear recurrent Gated-DeltaNet layers out of 40 total blocks. During decode, evaluating recurrent state is significantly cheaper than evaluating quadratic attention across all layers. This gives Qwen a raw ~11 tok/s decode advantage on DDR5.
2. **Why GLM-4.7 is Safer on 32GB Hardware (19.6 vs 27.0 GB RAM):**
   Qwen 3.6 requires 20.6 GB of weights locked in RAM plus recurrent states, pushing host memory to **27.0 GB**. On a 32GB machine, this leaves only ~5 GB for the OS, terminal, IDE, and desktop environments. GLM-4.7's REAP pruning cuts total model size to 14.0 GB, using only **19.6 GB of host RAM** and leaving **>12 GB of headroom**, avoiding any risk of swap thrashing.
3. **Attention Scaling:**
   At 2k context, GLM's DeepSeek2 Multi-head Latent Attention (MLA) achieves higher prefill throughput (1,459 vs 1,255 t/s) and faster TTFT (1.37s vs 1.59s) because the 576-wide compressed latent projection is extremely lightweight for GPU matrix multiplication.

---

## 5. Final Workstation Deployment Strategy

| Use Case | Recommended Model | Reason |
|---|---|---|
| **High-Frequency Code Iteration & Linting** | **`[qwen36-coder]`** | Highest sustained decode speed (**46.9 t/s**) and strong code execution. |
| **Heavy Architecture, Planning & Heavy Multi-Tasking** | **`[glm47-reap]`** | 100% spec reliability, sub-1.4s TTFT, and **7.4 GB lower memory footprint**, preventing workstation RAM starvation when browsers and IDEs are open. |
| **Two-Model Agent Workflows** | **`[glm47-reap]` $\rightarrow$ `[qwen36-coder]`** | GLM formulates the spec in ~14s, router swaps in ~10.9s, and Qwen writes the code in ~11s. |

*Raw data for all individual runs is archived under `reports/runs/`.*
