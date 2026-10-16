# Experiment 4: Rails AI Evals Benchmark (Local MoE)

## Objective
Benchmark the local Qwen 36B MoE running on `llama-server` against the official `rails/ai-evals` atomic suite, specifically targeting the `ar-erase-account` cascade deletion task that failed in previous cloud benchmarks (PR #5).

## Environment
* **Model:** Qwen 3.6 35B (`qwen36-coder`)
* **Endpoint:** `http://127.0.0.1:8080/v1/chat/completions` (Local RTX 3060)
* **Agent:** `miniswen`
* **Task:** `ar-erase-account` (GDPR Data Erasure)

## Telemetry & Cost
* **Duration:** 10.7 minutes (67 agent turns)
* **Input Tokens:** 1,483,574 (97.7% prompt caching hit rate; 1,449,339 cached)
* **Output Tokens:** 19,476
* **API Cost:** $0.00

## Verification Results: FAIL (2/5 Assertions Passed)
The model successfully handled standard row deletion but failed the complex relational requirements:
- ❌ Failed to handle legacy soft-deleted accounts.
- ❌ Failed to isolate private books (deletion) vs public books (re-bylining).

## Conclusion
The local orchestrator pipeline is fully functional and capable of handling massive multi-turn agent workflows (1.5M tokens) efficiently. However, the Qwen 35B model's reasoning capabilities hit a hard ceiling on complex relational data pipelines, confirming the necessity of Frontier-authored `ARCH_PLAN.md` architectural specs for complex tasks.
