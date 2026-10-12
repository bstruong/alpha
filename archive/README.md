# Archive

Material moved out of the Alpha critical path during the `berserker` → Alpha cleanup. Kept for history; not required for Circuit 1.

| Path | Former location | Notes |
|------|-----------------|-------|
| `polyglot-validation/` | `validation/`, `validation_v2/`, `validation_v3/` | Green-wash → TDD experiments |
| `benchmarks-legacy/` | `experiments/`, `ruby-rails-model-benchmark/`, `llm-benchmark/`, `opencode-agent-eval/` | One-off benches |
| `frontier-batteries/` | `tests/`, Flash `scripts/run_module*.py` | Flash / planner Python suites |
| `ops/` | `automation/n8n/` | Ops sidecar; Omega/ops later |
| `specs/` | `specs/` | Old ARCH_PLAN drafts |
| `bench.sh`, `.aider.conf.yml` | repo root | Misc |

**Kept at repo root (not archived):** `reports/` (includes 4-stone deliverables from PR #24), stone-suite scripts under `scripts/`, `engine/`, `harness/`, `prompts/`.

Do not add new work here — new scenarios go under `/scenarios`, harness code under `/lib/alpha` (scaffold PR).
