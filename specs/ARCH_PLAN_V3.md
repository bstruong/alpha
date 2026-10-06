---
repo: /home/user/Projects/hybrid-ai-harness
---

# Architecture Plan: Experiment 3 (Pure Ruby PII Airgap)

## Global Constraints
* Use pure Ruby (no Rails dependencies).
* You must pass `rubocop -A validation_v3/` and `ruby validation_v3/test_scrubber.rb` before declaring success.
* Do not modify `test_scrubber.rb`. Write the implementation code in `pii_scrubber.rb` until the tests pass.

## Tasks

### T01 — Pure Ruby PII Scrubber
```task
id: T01
phase: 1
depends: []
write: ["validation_v3/pii_scrubber.rb"]
read: ["validation_v3/test_scrubber.rb"]
acceptance: "ruby validation_v3/test_scrubber.rb && rubocop -A validation_v3/pii_scrubber.rb"
max_output_tokens: 1500
attempts: 5
```
Implement `validation_v3/pii_scrubber.rb` containing a `PiiScrubber` class. 
It must contain a `scrub(text)` method that uses standard Ruby regex to detect and replace Social Security Numbers with `[REDACTED_SSN]` and Email Addresses with `[REDACTED_EMAIL]`. It must be robust enough to leave standard 9-digit order numbers alone if they lack the SSN hyphenation format.
