# Comprehensive 4-Stone Benchmark Report: Local LLM Evaluation

**Evaluation Date:** October 10, 2026  
**Test Hardware:** AMD Ryzen 7 9700X (8C/16T, 32 MiB L3) | 32 GB DDR5-6000 CL36 (2×16 GB) | NVIDIA GeForce RTX 3060 12GB | Samsung 990 Pro  
**Operating Context:** Homelab Workstation with 32GB RAM balancing OS, Docker services (PostgreSQL, n8n, ChromaDB, etc.), and local inference engine.

---

## 1. Executive Summary & Model Overview

We evaluated the two frontier local coding models on workstation hardware across all **4 Stones** to make an evidence-based production promotion decision:

| Model Identity | Preset | Parameter / Arch | Total Weights | VRAM Footprint | Host DDR5 RAM | Core Architectural Trait |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **GLM-4.7-Flash-REAP-23B-A3B** | `glm47-reap` | 23B MoE (A3B active) | 13.14 GiB | ~6.4 GiB | **19.61 GB** | DeepSeek2 MLA (576-dim latent), REAP 25% pruned, KV shifting |
| **Qwen 3.6 35B Hybrid (Candidate)** | `qwen36-coder-hybrid` | 35B MoE (A3B active) | 20.61 GiB | **10.72 GiB** | **23.21 GB** | 8 GPU expert layers (`n-cpu-moe = 32`), Gated-DeltaNet recurrent state |
| **Qwen 3.6 35B Baseline** | `qwen36-coder` | 35B MoE (A3B active) | 20.61 GiB | 4.80 GiB | 26.94 GB | 100% CPU MoE (`cpu-moe = true`), recurrent checkpoints |

### Final Verdict & Recommendation
- **PROMOTED AS DEFAULT:** **`qwen36-coder-hybrid`** is officially promoted in `engine/workstation.env`.
- **Key Wins:**
  1. **Coding Reliability:** Solved **100%** of real-world production test failures across both user repositories (`caster` 72/72 passing, `saber` 138/138 passing). GLM hallucinated a module definition in `caster` and failed to recover on Turn 2.
  2. **Decode Speed:** **50.3 tok/s** single-slot and **46.1 tok/s** aggregate dual-slot (vs GLM's 35.0 tok/s solo / 34.7 tok/s aggregate).
  3. **Long-Context Prefill:** **1.85× to 2.76× faster prefill** than GLM at 16k–32k contexts due to Gated-DeltaNet SSM hybrid layers (1455.8 tok/s vs 526.9 tok/s at 32k).
  4. **32GB Homelab Coexistence:** Liberated **3.73 GB of host DDR5 RAM** over the baseline Qwen preset by shifting 8 expert layers to the RTX 3060, keeping host footprint at 23.2 GB with full `mlock` immunity under Docker container memory pressure.

---

## 2. Stone 1: Dual-Slot Simultaneous Concurrency (`parallel = 2`)

Tested simultaneous inference dispatched to Slot 0 and Slot 1 at the exact same millisecond to measure DDR5 memory-bus contention, TTFT jitter, and aggregate throughput:

| Metric | GLM-4.7-Flash-REAP (`glm47-reap`) | Qwen 3.6 Hybrid (`qwen36-coder-hybrid`) | Delta / Advantage |
| :--- | :--- | :--- | :--- |
| **Solo Baseline Decode** | 35.04 tok/s | **49.84 tok/s** | Qwen +42.2% |
| **Solo Baseline TTFT** | **0.979s** | 1.145s | GLM -14.5% |
| **Dual-Slot Slot 0 Decode** | 20.19 tok/s | **35.23 tok/s** | Qwen +74.5% |
| **Dual-Slot Slot 1 Decode** | 22.99 tok/s | **35.64 tok/s** | Qwen +55.0% |
| **Dual-Slot Slot 0 TTFT** | **0.922s** | 2.180s | GLM lower TTFT jitter |
| **Dual-Slot Slot 1 TTFT** | **1.927s** | 2.257s | GLM lower TTFT jitter |
| **Aggregate Dual-Slot Throughput** | 34.66 tok/s | **46.11 tok/s** | **Qwen +33.0% higher aggregate** |
| **Dual-Slot Efficiency Ratio** | 98.9% | 92.5% | Both maintain >92% bus efficiency |

**Insight:** Because `qwen36-coder-hybrid` offloads 8 layers of expert weights to VRAM, ~20% fewer memory accesses traverse the host DDR5 memory bus per token, allowing two simultaneous generation threads to sustain **46.1 tok/s aggregate** without starving the memory controller.

---

## 3. Stone 2: Real Production Repository Coding (`saber` & `caster`)

Evaluated the models as autonomous coding agents directly on the user's production Ruby on Rails repositories (`/home/user/Projects/saber` and `/home/user/Projects/caster`), testing against the actual RSpec suites backed by Docker PostgreSQL instances.

### 3A. Saber Repository (`/home/user/Projects/saber`)
- **Challenge:** Fix 5 test failures in `Interaction` (`Interaction::RECENT_WINDOW` scope) and `Reminder` (`Reminder#snoozed?` predicate and expired/future spec assertions).
- **Target Suite:** 138 RSpec examples.
- **Results:**
  - **`qwen36-coder-hybrid`:** **138 examples, 0 failures, 1 pending (100% PASS)**
    - Speed: 50.1–50.6 tok/s decode, TTFT 0.97–1.16s, Wall: 5.6s / 8.0s.
  - **`glm47-reap`:** **138 examples, 0 failures, 1 pending (100% PASS)**
    - Speed: 34.6–35.0 tok/s decode, TTFT 0.74–0.86s, Wall: 7.0s / 10.3s.

### 3B. Caster Repository (`/home/user/Projects/caster`)
- **Challenge:** Reconstruct and refactor the complete `ListingNormalizer` class (previously truncated with `# ...` in an aider ladder experiment) utilizing `Cents.to_cents(value)` across 28 converters, decimal parsing, and composite pipe delimiters.
- **Target Suite:** 72 RSpec examples (33 failing at baseline).
- **Results:**
  - **`qwen36-coder-hybrid`:**
    - **Turn 1 (Zero-Shot):** 39 passed, 33 failed (`NameError: undefined local variable or method 'mappings'`).
    - **Turn 2 (Autonomous Repair):** Received test error, accurately diagnosed the missing reader / `@mappings`, and fixed the code.
    - **Final Suite:** **72 examples, 0 failures (100% PASS)** in 15.9s (50.3 tok/s).
  - **`glm47-reap`:**
    - **Turn 1 (Zero-Shot):** 39 passed, 33 failed (declared `module ListingNormalizer` instead of `class ListingNormalizer` and redefined `module Cents`).
    - **Turn 2 (Autonomous Repair):** Re-attempted repair but failed to detect the `module` vs `class` declaration flaw; remained at 33 failures.
    - **Final Suite:** **33 failures (FAIL)**.

---

## 4. Stone 3: Long-Context Needle-in-a-Haystack (NIAH) Retrieval Fidelity

Tested retrieval fidelity at **16,000** and **32,000** token contexts with a cryptographic needle (`VAULT-ALPHA-7729-OMEGA`) placed at 50% depth within dense synthetic technical documentation.

| Context Target | Model | Exact Match | TTFT | Prefill Speed | Decode Speed | Total Wall Time |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **16,000 Tokens** | `glm47-reap` | **PASS (100%)** | 19.77s | 813.41 tok/s | 26.96 tok/s | 20.22s |
| **16,000 Tokens** | `qwen36-coder-hybrid` | **PASS (100%)** | **10.67s** | **1507.68 tok/s** | **44.97 tok/s** | **10.98s** |
| **32,000 Tokens** | `glm47-reap` | **PASS (100%)** | 60.88s | 526.95 tok/s | 23.54 tok/s | 61.40s |
| **32,000 Tokens** | `qwen36-coder-hybrid` | **PASS (100%)** | **22.05s** | **1455.77 tok/s** | **41.04 tok/s** | **22.39s** |

### Architectural Findings:
1. **Zero Recall Degradation:** Neither the 576-dim compressed MLA latent representation in GLM nor the hybrid recurrent states in Qwen suffered from quantization loss or recall degradation at 32k tokens.
2. **SSM Hybrid Scaling Advantage:** Qwen 3.6 Hybrid processed the 32k token prompt in **22.05s** (1455.8 tok/s), whereas GLM required **60.88s** (526.9 tok/s). Because Qwen only performs full attention on 10 of its 40 layers (the remaining 30 layers use linear recurrent state), prefill scales linearly with sequence length rather than quadratically.

---

## 5. Stone 4: Configuration Promotion & Homelab 32GB Coexistence

### Homelab 32GB Memory Allocation Breakdown
Under a 32GB physical RAM budget, host memory must coexist with Linux OS caches, KWin Wayland desktop, and Docker services (`postgres`, `n8n`, `chromadb`, etc.):

```
[ Workstation 32GB Physical DDR5 Budget ]
|-- Linux OS, Wayland, Desktop Services:        ~3.5 GB
|-- Homelab Docker Stack (Postgres, n8n, etc.): ~4.5 GB
|-- Available for Local LLM Engine:            ~24.0 GB
```

- **Qwen 3.6 Baseline (`qwen36-coder`):** Required **26.94 GB** host RAM. Under a busy container stack, this forced ~3 GB of memory into swap, introducing disk paging risks.
- **GLM-4.7 Flash REAP (`glm47-reap`):** Required **19.61 GB** host RAM. Left ample room for containers, but sacrificed 40% decode throughput and failed the complex Caster refactor.
- **Qwen 3.6 Hybrid (`qwen36-coder-hybrid`):** Requires **23.21 GB** host RAM while using 10.72 GB VRAM on the RTX 3060. With `mlock` active, all weights remain pinned in physical memory.

### Promotion Actions Completed
1. Updated `engine/workstation.env`:
   ```bash
   DEFAULT_PRESET="qwen36-coder-hybrid"
   ```
2. Real-world repositories `/home/user/Projects/saber` and `/home/user/Projects/caster` verified green:
   - `saber`: 138/138 passing (1 pending expected).
   - `caster`: 72/72 passing.
3. Clean shutdown executed via `./engine/bin/llama-down.sh`.
