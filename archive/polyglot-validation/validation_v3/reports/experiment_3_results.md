# Experiment 3: Pure Ruby PII Airgap Validation

## Objective
Evaluate the local Qwen 36B MoE model's ability to write production-grade Ruby under strict TDD and RuboCop static analysis.

## Results
- **Pass Rate:** 100% (3/3 Minitest Assertions).
- **Static Analysis:** Passed `rubocop -A` with 0 offenses.
- **Autonomy & Self-Correction:** Qwen successfully wrote the regex logic for SSNs and emails. When RuboCop failed the initial pass due to missing `Style/Documentation`, Pi automatically fed the error back to the context window, and Qwen added the documentation and re-verified.
- **Artifacts:** A standalone `PiiScrubber` class ready for n8n integration.
