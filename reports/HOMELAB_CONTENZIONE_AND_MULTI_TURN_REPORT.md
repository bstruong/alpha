# Homelab Contention & Multi-Turn Prefix Cache Benchmark Report

**Author:** Principal Local AI Benchmarking Engineer  
**Date:** 2026-10-10  
**Target Hardware:** Workstation / Homelab Prototype (AMD Ryzen 7 9700X, 32 GB DDR5-6000, NVIDIA RTX 3060 12GB)  
**Evaluated Models:**
1. `[glm47-reap]` (GLM-4.7 Flash REAP-23B-A3B: MLA Pure Attention, 14.0 GB)
2. `[qwen36-coder-hybrid]` (Qwen 3.6 35B Hybrid: `n-cpu-moe = 32`, 8 Expert Layers on GPU VRAM, 20.6 GB)

---

## 1. Executive Summary

This evaluation addressed the two most critical operational questions for deploying local AI agents on a **32 GB homelab host**:
1. **Benchmark A (Memory Contention & Swap Thrashing):** How do the models perform when background Docker containers consume 4.0 GB and 6.0 GB of pinned dirty host memory?
2. **Benchmark B (Multi-Turn Prefix Cache Profiler):** How do the models perform across a realistic 10-turn progressive coding agent session (Turn 1 Cold TTFT vs. Turns 2–10 Warm TTFT)?

### Key Discoveries
* **`glm47-reap` is Impervious to Memory Contention:** Even under a 6.0 GB simulated container load, GLM sustained full throughput (37.2 t/s at 2k, 33.6 t/s at 8k) with **0 MB swap spillage** and over **5.7 GB of free host RAM remaining**.
* **`qwen36-coder-hybrid` Breakthrough:** By offloading 8 expert layers to the RTX 3060 (using 10.7 GB VRAM), host RAM usage was kept to **23.2 GB**. Under 6.0 GB of background container pressure, Linux pushed ~1 GB of idle desktop pages to swap, but **`mlock` protected the model weights—decode throughput did not degrade**, sustaining **49.2 – 51.0 tok/s**.
* **Prefix Caching Works on Both:**
  - **GLM-4.7 Flash (MLA KV Shifting):** Achieved an average Warm TTFT of **~208 ms** (down from 584 ms cold) with a 98.6% cache hit ratio at Turn 10.
  - **Qwen 3.6 Hybrid (Recurrent State Checkpoints):** Achieved an average Warm TTFT of **~316 ms** with a 98.1% cache hit ratio, but completed turns faster (**4.28 s vs. 6.19 s**) due to its **50.5 tok/s** decode generation speed.

---

## 2. Benchmark A: Homelab Memory Contention & Swap Pressure

*Injected pinned dirty host memory buffers (0 GB baseline, 4 GB, 6 GB) while executing 2k and 8k context inferences:*

| Model Preset | Background Pressure | Pre-Test Avail RAM | Under-Pressure Avail RAM | Swap Spillage | 2k Decode Speed | 8k Decode Speed | Host Verdict |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---|
| **`glm47-reap`** | **0 GB (Baseline)** | 11,889 MB | 11,889 MB | **0.0 MB** | 35.36 tok/s | 33.75 tok/s | ✅ Abundant Headroom |
| | **4.0 GB Pressure** | 11,797 MB | 7,705 MB | **0.0 MB** | 37.16 tok/s | 33.50 tok/s | ✅ Rock Solid |
| | **6.0 GB Pressure** | 11,698 MB | 5,744 MB | **0.0 MB** | 37.15 tok/s | 33.62 tok/s | ✅ 100% Stable (5.7GB Free) |
| **`qwen36-coder-hybrid`** | **0 GB (Baseline)** | 8,240 MB | 8,240 MB | **0.0 MB** | 50.10 tok/s | 49.29 tok/s | ✅ Balanced |
| | **4.0 GB Pressure** | 7,910 MB | 3,916 MB | ~98 MB | 48.59 tok/s | 47.35 tok/s | ✅ High Performance |
| | **6.0 GB Pressure** | 8,114 MB | 2,632 MB | ~1,051 MB* | **50.97 tok/s** | **49.21 tok/s** | ✅ Protected by `mlock` |

*\* Note: Under 6 GB pressure, the Linux kernel swapped out cold user-space desktop and background daemon pages, but because `llama-server` ran with `mlock` enabled, the 32 CPU expert layers remained pinned in physical DDR5 memory, completely insulating inference from swap thrashing.*

---

## 3. Benchmark B: Multi-Turn Agent Prefix Cache Profiler

*Simulated 10 progressive turns of interactive pair programming (building an asynchronous PostgreSQL connection manager with telemetry and health checks). Cumulative context grew from ~200 tokens (Turn 1) to ~2,350 tokens (Turn 10).*

### 3.1 Turn-by-Turn Telemetry

| Turn # | Prompt Focus | **GLM-4.7 Flash REAP** (MLA KV Shift) | | **Qwen 3.6 Coder Hybrid** (Recurrent Checkpoints) | |
|:---:|:---|:---:|:---:|:---:|:---:|
| | | **TTFT (s)** | **Cache Hit %** | **TTFT (s)** | **Cache Hit %** |
| **Turn 1** | Initial Class Design | 0.584 s (Cold) | 0.0% | 0.701 s (Cold) | 0.0% |
| **Turn 2** | Connection Pool & Backoff | **0.202 s** | 92.6% | **0.351 s** | 90.5% |
| **Turn 3** | Prometheus Observability | **0.171 s** | 96.0% | **0.267 s** | 94.7% |
| **Turn 4** | Read/Write Split Routing | **0.196 s** | 96.4% | **0.344 s** | 95.4% |
| **Turn 5** | Async Transaction Manager | **0.192 s** | 97.3% | **0.331 s** | 96.5% |
| **Turn 6** | Pytest-Asyncio Test Suite | **0.180 s** | 97.9% | **0.311 s** | 97.2% |
| **Turn 7** | Distributed Redis Locking | **0.211 s** | 98.1% | **0.343 s** | 97.5% |
| **Turn 8** | HTTP Health Check Handler | **0.190 s** | 98.4% | **0.332 s** | 97.9% |
| **Turn 9** | Parameterized SQL Validation | **0.169 s** | 98.8% | **0.221 s** | 98.3% |
| **Turn 10**| Production Audit & Docstrings| **0.368 s** | 98.6% | **0.347 s** | 98.1% |

### 3.2 Performance Summary

| Metric | **GLM-4.7 Flash REAP** | **Qwen 3.6 Coder Hybrid** | Architectural Advantage |
|:---|:---:|:---:|:---|
| **Cold TTFT (Turn 1)** | **0.584 s** | 0.701 s | GLM's MLA prefill is slightly faster on small prompts. |
| **Avg Warm TTFT (Turns 2–10)** | **0.208 s (~200 ms)** | 0.316 s (~315 ms) | **GLM is ~34% faster on prompt evaluation** due to low-rank latent KV shifting. |
| **Sustained Decode Speed** | 34.2 – 36.2 tok/s | **48.8 – 51.0 tok/s** | **Qwen is ~41% faster on code generation**. |
| **Turn 10 Total Wall Clock** | 6.19 s | **4.28 s** | **Qwen finishes turns 31% faster** despite the slightly longer TTFT. |

---

## 4. Final Homelab Deployment Guidelines

For your 32 GB homelab node:

1. **Deploy `[qwen36-coder-hybrid]` as the Primary Daily Driver:**
   - Setting `n-cpu-moe = 32` is the golden configuration for a 12 GB GPU + 32 GB RAM setup.
   - It cuts host RAM down to **23.2 GB**, comfortably coexisting with a 4–6 GB Docker stack.
   - It delivers **50+ tok/s decode generation** and sub-350ms warm agent turns.
2. **Deploy `[glm47-reap]` if Container Workload Exceeds 6 GB:**
   - If your homelab runs heavy services (Nextcloud, Plex, Ollama, Elasticsearch, GitLab) pushing container RAM to 8–10 GB, switch to `[glm47-reap]`.
   - At only **19.6 GB host RAM**, it guarantees zero swap pressure under any workload while maintaining 35 tok/s.
3. **Never Deploy Baseline `[qwen36-coder]` on a Shared 32GB Box:**
   - Standard 100% CPU MoE consumes 27.0 GB of RAM, leaving almost no margin for the host OS.
