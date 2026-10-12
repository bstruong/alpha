# Experiment 1: Frontier-to-Local Handoff (Validation Suite)

## Overview
**Date:** October 5, 2026  
**Objective:** Evaluate the local AI stack (llama-server + Qwen 3.6 35B + Pi Harness + n8n) using a Frontier-authored `ARCH_PLAN.md` to autonomously generate a polyglot Validation & Benchmark Suite.

## Telemetry & Execution Results
* **Performance:** Qwen generated code at ~54 tokens/sec on the RTX 3060.
* **TTFT:** Averaged ~2.8s - 3.0s (Note: Later identified as an implementation flaw in the measurement script, not the engine).
* **Hardware Stability:** Zero VRAM/Swap drift detected during the 30s soak test.
* **Autonomy:** Qwen processed the entire 4-phase architectural plan. It generated 290 lines of Python zero-shot for the CLI runner and correctly scaffolded polyglot tests in Go, Java, TypeScript, and Python.

## Critical Flaws Identified (The "Green-Washing" Problem)
A high-effort Gemini 3.8 Flash code review exposed severe logic flaws that the local model masked via superficial testing:
1. **Faked TTFT:** Qwen used blocking HTTP requests, effectively measuring the total generation time instead of actual TTFT.
2. **Inverted Memory Logic:** The `soak` test penalized freed swap memory, treating it as a memory leak.
3. **Empty Go Logic:** Qwen compiled an empty `main()` function in Go and reported the test as a pass.
4. **Brittle Transpilation:** Qwen used `sed` to strip TypeScript types because `ts-node` was missing, accidentally corrupting core JavaScript logic (`.map(Number)`).
5. **Argparse Crash:** A missing `--dry-run` attribute crashed the global `all` command due to poor variable scoping.

## Conclusions & Lessons for Experiment 2
While the hardware, engine, and orchestrator harness are highly capable, the local MoE model requires significantly stricter systemic guardrails to prevent logical hallucinations and "green-washed" code. 

**Required Fixes for Experiment 2:**
1. **Cloud-Mandated TDD:** Frontier models must write the unit tests before execution.
2. **Modern Toolchain Verification:** Equip the harness with `ruff`, `uv`, and `pyright` to provide instantaneous static analysis feedback to the local model.
3. **Strict Constraints:** Forbid `sed` transpilation in `AGENTS.md` and enforce missing dependency resolution.
