# Qwen 3.8 Flash Benchmark Report (Workstation)

**Canonical aggregate** of Flash benchmark iterations on Workstation.  
**Date range:** 2026-10-07 (v1 exploratory → v3 full suite → v3+ Module 1+2 refresh)  
**Do not re-run from this doc** unless you intend to burn ~45–75 minutes of wall time with the engine up.

Related artifacts:

| Artifact | Role |
|----------|------|
| [`FRONTIER_EVAL_SCORECARD.md`](FRONTIER_EVAL_SCORECARD.md) | Latest scorecard (M1+M2 refreshed; §3 pipeline may be stale) |
| [`frontier_full_eval.json`](frontier_full_eval.json) | Merged machine-readable results |
| [`module1_telemetry.json`](module1_telemetry.json) / [`module2_spec_traps.json`](module2_spec_traps.json) | Per-module dumps for latest Flash M1+M2 |
| [`STACK_TECHNOLOGY_BRIEF.md`](STACK_TECHNOLOGY_BRIEF.md) | Deep stack research (llama.cpp / Pi / spec-wins / fork wiki) |
| [`NEXT_BENCHMARK_RUN.md`](NEXT_BENCHMARK_RUN.md) | How to re-run modules (engine start required) |
| [`AGENT_HANDOFF.md`](AGENT_HANDOFF.md) | Short session status pointer |
| [`HYPERBOLIC_LEGACY_FILE_NOTE.md`](HYPERBOLIC_LEGACY_FILE_NOTE.md) | Root-cause note for accidental HTC leftover |

Historical host logs (not in git): `/tmp/frontier_benchmark.log`, `/tmp/frontier_benchmark_v3.log`, `/tmp/frontier_m1_flash.log`, `/tmp/frontier_m2_flash.log`.

---

## 1. Hardware and stack

| Item | Value |
|------|--------|
| Host | **Workstation** — AMD Ryzen 7 9700X (8C/16T), RTX 3060 12GB, 32GB DDR5, Samsung 990 Pro NVMe (Btrfs zstd:3) |
| Engine binary | Custom CUDA `llama-server` at `experiments/llama.cpp-qwen4exp/build/bin/llama-server` (commit `4d756bc+`, **qwen4exp**). System package `llama.cpp-cuda` b10631 lacks `LLM_ARCH_QWEN4EXP`. |
| Router | `llama-up.sh router … --models-max 1` (one resident model; Flash↔Tier-1 swaps unload/load) |
| Flash preset | `[qwen3.8-flash]` / alias `qwen-3.8-flash` — `load-mode = mmap`, `n-cpu-moe = 56`, `ctx-size = 69632`, `parallel = 1`, `spec-type = none`, KV `q4_0` |
| Tier-1 worker | `[qwen36-coder]` — RAM-resident path (`mlock` / `cpu-moe` when memlock allows) |
| Flash weights | ~80 GB sharded GGUF under `models/Qwen3.8-Flash-Next-AD-3.84bpw-IQ4_XS-M64/` (gitignored `*.gguf`) |
| Pi | `harness/pi/models.json` Flash `contextWindow: 69632` (matches preset) |

**32GB ceiling:** Flash experts do not fit in RAM. Decode is NVMe/page-cache bound. Tier-1 (~20 GB experts) is the RAM-resident daily driver; Flash is the specialist reasoner.

---

## 2. Harness evolution (v1 → v3+)

| Stage | What changed |
|-------|----------------|
| **v1** | Monolithic `run_full_benchmark.py`; weak grading; tokenizer fallback noise; Flash decode ~1.71→0.13 t/s across 2k→64k; A/B/C all FAIL |
| **v2/v3** | Repro knobs (`temperature 0`, `seed 12345`, `cache_prompt: false`); `slot-save-path` + erase between modules/traps; execution oracles for Tests A/B; soft Test C scratchpad; grade `content` + `reasoning_content`; per-trap metrics |
| **v3+** | **Independent modules** (`run_module1_telemetry.py`, `run_module2_spec_traps.py`, `run_module3_pipeline.py`); telemetry **primary = 2k/8k**, 32k/64k marked `nvme_bound` with decode window cap; Test C **named deliverables** (`merge_sort` + `fib`/`fibonacci`) + one corrective retry; Module 3 **planner `max_tokens=700`** + Phase 1.1 bullets-only |

Canonical Flash client id: **`qwen3.8-flash`**. Speculative decoding A/B kept `spec-type = none` (ngram-mod accepted drafts but did not beat NVMe-bound decode).

---

## 3. Results timeline

### 3.1 Early Flash full suite (v1, historical)

Source: `/tmp/frontier_benchmark.log` (not committed).

| Context | TTFT (s) | Prefill (t/s) | Decode (t/s) |
|---------|----------|---------------|--------------|
| 2000 | 12.397 | 161.33 | **1.71** |
| 64000 | 30.129 | 2124.18 | **0.13** |

- Spec traps: **A FAIL / B FAIL / C FAIL**
- Pipeline: swap ~10.3 s; worker success false (early handoff grader)

### 3.2 v3 full suite (~73 min wall, A/B PASS, C FAIL)

Source: `/tmp/frontier_benchmark_v3.log` + retained pipeline block in `frontier_full_eval.json`.

Rough wall: M1 ~12.5 min (incl. uncapped 32k/64k decode) + M2 ~30–35 min + M3 planner-heavy (~23 min with retry) ≈ **~70–75 min**.

| Module | Result |
|--------|--------|
| Telemetry (sample) | 2k decode **2.0** t/s; 8k **1.0** t/s; 32k/64k ~0.22/0.21 t/s (full decode measured) |
| Spec traps | **A PASS**, **B PASS**, **C FAIL** (`has_merge: false` — fib present, merge_sort missing) |
| Pipeline | Swap **11.468 s**, worker **11.433 s**, worker success ✅ — overall **HEALTHY**, but planner **`wall_sec` ≈ 1366** / `completion_tokens` 5000 across 2 requests (expensive) |

### 3.3 Latest: Module 1 + Module 2 only (v3+, 2026-10-07)

Sources: scorecard + `module1_telemetry.json` / `module2_spec_traps.json`. Engine stopped after run. **Module 3 not re-run.**

#### Telemetry (primary = 2k/8k)

| Context | TTFT (s) | Prefill (t/s) | Decode (t/s) | Peak RAM (MB) | Peak VRAM (MB) | Role |
|---------|----------|---------------|--------------|---------------|----------------|------|
| 2000* | 14.267 | 140.19 | **2.13** | 3772 | 7327 | Primary |
| 8000* | 30.035 | 266.36 | **1.01** | 3541 | 7331 | Primary |
| 32000† | 30.073 | 1064.09 | 0.0† | 3388 | 7333 | NVMe-bound secondary |
| 64000† | 30.136 | 2123.73 | 0.0† | 3307 | 7333 | NVMe-bound secondary |

\* Primary regression gate. † Decode window capped at 60s; not a primary signal.

Wall: M1 ~341 s (~5.7 min); M2 ~2058 s (~34.3 min); per-trap ≈ A 748s / B 949s / C 332s.

#### Spec traps

| Test | Result | Notes |
|------|--------|-------|
| **A** Precision Guard | ✅ PASS | Oracle + model pytest green |
| **B** Multi-file consistency | ✅ PASS | Oracle confirmed `tenant_id, user_id, amount` reach core |
| **C** Named deliverables | ✅ PASS | `merge_sort` + fib present; no retry needed |

#### Pipeline (stale — retained from §3.2)

Scorecard §3 still shows the prior HEALTHY pipeline with expensive planner. Re-run `scripts/run_module3_pipeline.py` under router when ready to refresh.

---

## 4. Verdict

**Qwen 3.8 Flash on Workstation is a specialist reasoner, not a daily driver.**

- **Strengths:** With v3+ oracles and deliverable grading, Flash clears precision and multi-file traps that earlier harnesses (and Tier-1 alone) missed. Useful as planner / architect / hard-reviewer when quality justifies slow tokens.
- **Limits:** Primary decode is ~**2.1 / 1.0 t/s** at 2k/8k under mmap. Long-context decode is NVMe-bound. Full-suite wall time is dominated by Flash generation, especially planner phases without a tight token cap.
- **Tier-1 (`qwen36-coder`):** Keep as coding / iteration engine (RAM-resident, ~tens of t/s class when healthy).
- **Hardware truth:** **32GB is the ceiling** for this Flash quant — you cannot mlock the expert set; mmap+paging is mandatory.

---

## 5. Ideal workflows on this hardware

1. **Daily coding:** Router or single-model **Tier-1** only. Do not leave Flash resident.
2. **Hard architecture / spec traps / review:** Load **Flash** for a bounded planning pass (`max_tokens` capped, bullets-only phase prompts), write `specs/*.md`, then **swap to Tier-1** for implementation (`models-max 1` makes this an explicit unload/load).
3. **Benchmarks:** Prefer independent modules; use 2k/8k as the regression gate; treat 32k/64k as secondary stress only.
4. **Avoid:** Interactive coding loops on Flash; ngram speculation expecting free speedups on mmap MoE; forcing full 256k KV for Flash on 12GB VRAM.

---

## 6. What this PR ships (code + docs)

- `tests/benchmark_suite/` — common knobs, reporting, telemetry, spec traps + fixtures, pipeline
- `scripts/run_module{1,2,3}_*.py`, `run_full_benchmark.py` — independent runners
- Engine/harness Flash enablement: `engine/models.ini` Flash preset + slot-save-path, `workstation.env` → qwen4exp binary, `setup-memlock.sh` mkdir fix, Pi Flash model entry, `pi-monitored.sh` model→preset mapping
- Reports: this file, scorecard, JSON dumps, stack brief, trimmed handoff / next-run docs

**Intentionally not committed:** root `models.ini` duplicate, `fix_preset.py`, root `pipeline_results.json`, `experiments/llama.cpp-qwen4exp/` build tree, GGUF weights, PID files, `/tmp` logs, legacy `experiments/hyperbolic-time-chamber/` (see note below).
