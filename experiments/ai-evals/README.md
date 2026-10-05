# AI Evals Experiment Archive

This directory contains evaluation benchmarks, verification logs, and patches from agentic coding experiments on Ruby on Rails codebases.

## Deliverables & Findings
- **Primary Report:** [Qwen 3.8 27B Atomic Task Evaluation Report](reports/REPORT_QWEN3.8_27B_ATOMIC_TASKS.md)
  - 63 evaluation runs across 21 complex Rails tasks
  - 76.2% overall pass rate (48/63)
  - Cost, duration, and failure mode analysis

## Directory Structure
- **`reports/`**: Synthesized evaluation reports and performance scorecards (permanent deliverables).
- **`runs/2026-08-24-atomic-tasks-new-models/qwen3.8-27b/`**:
  - `agent.patch`: Actual code diff produced by the agent.
  - `checks.json`: Verifier test assertion results.
  - `result.json`: Trial duration, token count, cost, and metadata.
  - `verifier.log`: Standard output from automated test runs.
