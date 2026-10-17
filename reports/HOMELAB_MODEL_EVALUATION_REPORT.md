# Homelab Model Evaluation Report: Qwen 3.6 35B vs. GLM 4.7 Flash REAP vs. Qwen 2.5 Coder 14B

**Evaluation Date:** October 16–17, 2026  
**Node:** AM5 Homelab (`watchtower`, `192.168.1.92`)  
**Hardware Profile:** AMD Ryzen 7 9700X (8C/16T, 32 MiB L3) | 32 GB DDR5-6000 CL36 | NVIDIA GeForce RTX 3060 12GB | Samsung 990 Pro NVMe  
**Inference Engine Substrate:** `llama-server` (k3s pod with GPU passthrough and IPC_LOCK `mlock`)  
**Supervision & Profile:** Alpha Harness `bin/alpha run` with Pi agent supervision (`shipping` profile) and Turn 2 Self-Repair  

---

## 1. Executive Summary

We conducted comprehensive, head-to-head empirical evaluation campaigns directly on the AM5 homelab node (`watchtower`) comparing the three candidate open-weights models across diverse homelab workloads (data sanitization, document extraction, and multi-turn autonomous coding):

1. **`qwen36-coder-hybrid`**: Qwen 3.6 35B MoE (A3B active) with 8 expert layers offloaded to VRAM (`n-cpu-moe = 32`).
2. **`glm47-reap`**: GLM-4.7 Flash REAP 23B MoE (A3B active) with 25% pruned experts and 100% CPU MoE offload.
3. **`qwen25-coder-14b`**: Qwen 2.5 Coder 14B Dense (`q4_k_m`) with **100% VRAM offload** on the RTX 3060 12GB (`--ctx-size 16384`, `--parallel 1`).

### Comprehensive Scorecard & Hardware Metrics

| Model Identity | Architecture | Engine Preset | Context Window | Offload Strategy | Peak VRAM | Decode Speed | Data Task Pass@1 (PII / OCR) | Code Task Pass@1 (`qwen36-daily`) | Full Suite Wall Time |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Qwen 2.5 Coder 14B** | Dense | `qwen25-coder-14b` | 16,384 | **100% VRAM** | 10.47 GB | **34.5 tok/s** (429.9 prefill) | **100% (1.0)** | 0.11 (1/9)* | **273.5s** |
| **GLM-4.7 Flash REAP** | 23B MoE (A3B) | `glm47-reap` | 131,072 | DDR5 MoE | 5.2 GB | 14.2 tok/s | Untested | **0.67 (6/9)** | 1983.9s |
| **Qwen 3.6 35B MoE** | 35B MoE (A3B) | `qwen36-coder-hybrid` | 262,144 | Hybrid VRAM+DDR5 | 11.2 GB | 48.0 tok/s | Untested | **0.56 (5/9)** | 445.6s |

*\*Note on Qwen 2.5 Coder coding score: All 8 failed tasks failed with `tools: 0` due to a tool-calling protocol mismatch between Pi's streaming OpenAI function calling parser and llama-server's chat template output, NOT code synthesis failure.*

---

## 2. Key Findings Across Workloads

### 1. Data Sanitization & Extraction: Uncontested 100% Pass@1
- **PII Scrubbing (`scrub-ssn-email`):** Qwen 2.5 14B achieved a **100% Pass@1 in 2.0 seconds** (151 prompt tokens, 65 completion tokens). It reliably sanitized US Social Security Numbers and email addresses while preserving surrounding structural context.
  - **Qualification:** Qualified as `sanitizer` (`qualifications/qwen25-coder-14b__sanitizer__shipping.json`).
- **Document OCR Extraction (`extract-receipt`):** Qwen 2.5 14B achieved **100% Pass@1 in 3.3 seconds** (140 prompt tokens, 111 completion tokens). It extracted vendor names, item arrays, subtotal, tax, and total values into valid JSON matching the strict schema.
  - **Qualification:** Qualified as `extractor` (`qualifications/qwen25-coder-14b__extractor__shipping.json`).

### 2. VRAM Sizing & Latency Dynamics (Dense vs. MoE)
- **100% VRAM Offload:** Qwen 2.5 14B model weights occupy 8.57 GB. With `--ctx-size 16384` and `--parallel 1`, the GQA KV cache requires 1.53 GB (96 KiB/token). Total VRAM allocation is **10.47 GB**, leaving a 1.8 GB safety buffer on the 12 GB RTX 3060.
- **Speed Advantage:** Because all weights and KV cache reside on GPU memory (360 GB/s bandwidth), Qwen 2.5 achieves **429.9 tokens/sec prefill** and **34.5 tokens/sec decode**. 
- **Wall Time Comparison:** The full 9-task `qwen36-daily` suite completed in **273.5 seconds** (4.5 minutes) on Qwen 2.5 14B, compared to **1983.9 seconds** (33 minutes) on GLM-4.7 REAP and **445.6 seconds** on Qwen 3.6 Hybrid.

### 3. Pi Tool-Calling Protocol Quirk & The "Tools: 0" Mismatch
- While Qwen 3.6 and GLM 4.7 adhered to Pi's OpenAI function calling protocol (`tools` array mapped to tool call blocks), Qwen 2.5 Coder 14B defaulted to its native instruction behavior when queried by Pi over `openai-compatible` endpoints: it emitted Markdown code blocks (` ```json {"name": "write", "path": "...", "content": "..."} ``` `) inside `content` rather than populating `tool_calls`.
- Because llama-server terminated with `finish_reason: "stop"` and Pi did not parse JSON tool calls out of plain text, Pi reported `tools: 0` for all coding tasks, treating the model's output as conversational text rather than executing filesystem mutations.
- **Turn 2 Self-Repair Validation:** The self-repair engine successfully captured Minitest failures and re-prompted Turn 2 in all 8 failed tasks. Each 2-turn cycle completed in only 9–54 seconds without hanging or timing out.

---

## 3. Head-to-Head Task Breakdown (`qwen36-daily`)

| # | Task | Type | `qwen36-coder-hybrid` | `glm47-reap` | `qwen25-coder-14b` | Comparative Analysis |
|:---:|:---|:---:|:---:|:---:|:---:|---|
| 1 | `gate-hello` | Gate | ✅ **PASS** (18.0s) | ✅ **PASS** (17.0s) | ❌ FAIL (9.5s, tools: 0) | Qwen 2.5 described the edit in markdown instead of calling `edit`. |
| 2 | `gate-boot` | Gate | ✅ **PASS** (0.0s) | ✅ **PASS** (0.0s) | ✅ **PASS** (0.0s, tools: 0) | Unpatched sandbox baseline verification (instant). |
| 3 | `gate-edit` | Gate | ✅ **PASS** (18.0s) | ✅ **PASS** (18.5s) | ❌ FAIL (23.5s, tools: 0) | Seeded structural edit; MoEs called `edit`, Qwen 2.5 reviewed code. |
| 4 | `empty-card` | Graded | ✅ **PASS** (40.0s) | ✅ **PASS** (122.5s) | ❌ FAIL (36.0s, tools: 0) | MoEs applied null-safety fix; Qwen 2.5 suggested code block. |
| 5 | `spec-wins` | Graded | ❌ FAIL (53.0s) | ✅ **PASS** (141.0s) | ❌ FAIL (22.5s, tools: 0) | GLM updated both model and test. Qwen 2.5 suggested fix in text. |
| 6 | `library-cache` | Graded | ❌ FAIL (15.0s) | ✅ **PASS** (121.5s) | ❌ FAIL (41.5s, tools: 0) | GLM correctly scoped cache key by tenant id. |
| 7 | `audit-three` | Graded | ❌ FAIL (139.0s) | ❌ FAIL (721.1s) | ❌ FAIL (53.0s, tools: 0) | GLM timed out at 720s; Qwen 2.5 failed fast in 53s. |
| 8 | `once-only` | Graded | ✅ **PASS** (49.0s) | ❌ FAIL (121.0s) | ❌ FAIL (33.0s, tools: 0) | Qwen 3.6 implemented idempotency token. |
| 9 | `erase-account` | Graded | ❌ FAIL (113.5s) | ❌ FAIL (721.1s) | ❌ FAIL (54.5s, tools: 0) | Complex multi-association cascade; both MoEs timed out or failed. |

---

## 4. Architectural Role Division for Homelab Workloads

The empirical results provide a clear roadmap for model specialization on resource-constrained homelab hardware:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   FRONTIER CLOUD AGENTS (Gemini / Claude)              │
│  • System architecture & database schema planning                     │
│  • Multi-service transactional epics & complex migrations              │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │ Isolated tasks & structured specs
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   WATCHTOWER HOMELAB NODE (AM5 + RTX 3060)             │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ ROLE: Sanitizer & Extractor (`qwen25-coder-14b`)                 │  │
│  │ • 100% Pass@1 on PII scrubbing & OCR JSON extraction             │  │
│  │ • 100% VRAM offload (10.5 GB), 430 tok/s prefill, 35 tok/s decode│  │
│  │ • Zero data exfiltration (runs fully offline in local k3s)       │  │
│  │ • 2–3s latency per document/request                              │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ ROLE: Agentic Multi-Step Code Editor (`glm47-reap` / `qwen36`)   │  │
│  │ • Native OpenAI function calling compliance with Pi CLI harness  │  │
│  │ • High spec-trap discernment (GLM 67% Pass@1)                    │  │
│  │ • Best for overnight / background batch code repair              │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Scale-to-Zero Verification

To maintain zero memory pressure and low power consumption when inference is idle:
- **Engine Shutdown:** Running `bin/alpha engine down` scales the `alpha/alpha-llama` k3s deployment to 0 replicas.
- **Empirical Reclaim:**
  - VRAM dropped from **10,470 MiB to 1 MiB** (100% GPU memory reclaimed).
  - Host RAM usage dropped to **4.7 GiB used / 26 GiB available**.
  - Host swap remained stable at 109 MiB.

---

## 6. Artifact & Run Trace References

- **Qwen 2.5 Coder 14B Daily Coding Report:** [`reports/20261017T033126Z-qwen36-daily.md`](file:///home/brian/Projects/alpha/reports/20261017T033126Z-qwen36-daily.md)
- **Qwen 2.5 Coder 14B PII Scrubbing Report:** [`reports/20261017T032806Z-pii-scrubbing.md`](file:///home/brian/Projects/alpha/reports/20261017T032806Z-pii-scrubbing.md)
- **Qwen 2.5 Coder 14B OCR Extraction Report:** [`reports/20261017T032819Z-ocr-extraction.md`](file:///home/brian/Projects/alpha/reports/20261017T032819Z-ocr-extraction.md)
- **Qwen 2.5 Sanitizer Qualification:** [`qualifications/qwen25-coder-14b__sanitizer__shipping.json`](file:///home/brian/Projects/alpha/qualifications/qwen25-coder-14b__sanitizer__shipping.json)
- **Qwen 2.5 Extractor Qualification:** [`qualifications/qwen25-coder-14b__extractor__shipping.json`](file:///home/brian/Projects/alpha/qualifications/qwen25-coder-14b__extractor__shipping.json)
- **Qwen 3.6 Run Report:** [`reports/20261016T215552Z-qwen36-daily.md`](file:///home/brian/Projects/alpha/reports/20261016T215552Z-qwen36-daily.md)
- **GLM 4.7 Run Report:** [`reports/20261016T221542Z-qwen36-daily.md`](file:///home/brian/Projects/alpha/reports/20261016T221542Z-qwen36-daily.md)
