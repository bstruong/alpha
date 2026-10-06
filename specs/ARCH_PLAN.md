---
repo: /home/brian/Projects/berserker
---

# Architecture Plan: Validation & Benchmark Suite

## Global Constraints
* Use only Python 3 Standard Library (no third-party pip dependencies like `requests` or `psutil` allowed). Use `urllib.request` for API calls and `subprocess` for system metrics.
* All metrics must be saved to `validation/results/<timestamp>/metrics.json`.
* Adhere strictly to the Bounded Execution guardrails: write concise code, do not exceed the phase limits.

## Tasks

### T01 — Base Runner & CLI Scaffolding
```task
id: T01
phase: 1
depends: []
write: ["validation/run_suite.py"]
read: []
acceptance: "python3 validation/run_suite.py --help"
max_output_tokens: 1000
attempts: 3
```
Create the `validation/run_suite.py` executable script. Implement an `argparse` CLI with the following subcommands: `perf`, `quality`, `soak`, and `all`. Ensure the script sets up a timestamped results directory at `validation/results/<timestamp>/`.

### T02 — Performance & Token Metrics (perf)
```task
id: T02
phase: 2
depends: [T01]
write: ["validation/run_suite.py"]
read: ["validation/run_suite.py"]
acceptance: "python3 validation/run_suite.py perf --dry-run"
max_output_tokens: 2000
attempts: 3
```
Implement the `perf` subcommand logic. It must send a synthetic payload to `http://127.0.0.1:8080/v1/chat/completions` and calculate:
- Cold TTFT (Time-To-First-Token)
- Warm TTFT (Identical prompt sent twice)
- Append TTFT (Same prompt + new suffix)
- Prefill and Decode tokens/sec (parse the JSON response usage stats).

### T03 — Memory Soak & Stability Monitor (soak)
```task
id: T03
phase: 3
depends: [T01]
write: ["validation/run_suite.py"]
read: ["validation/run_suite.py"]
acceptance: "python3 validation/run_suite.py soak --duration 5"
max_output_tokens: 2000
attempts: 3
```
Implement the `soak` subcommand logic. It must run a background loop that samples system memory every 5 seconds using `subprocess`. Collect:
- `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits`
- Parse `/proc/meminfo` for `MemAvailable` and `SwapFree`.
- Fail the suite if VRAM drift > 256MB or Swap growth > 256MB.

### T04 — Polyglot Code Quality Harness (quality)
```task
id: T04
phase: 4
depends: [T01]
write: ["validation/run_suite.py"]
read: ["validation/run_suite.py"]
acceptance: "python3 validation/run_suite.py quality --dry-run"
max_output_tokens: 2000
attempts: 3
```
Implement the `quality` subcommand logic. It must iterate over directories in `validation/tasks/` (e.g., `python-token-bucket`, `go-merge-intervals`, `java-lru-cache`, `ts-semver-compare`), execute the test commands defined in those tasks, and record the pass/fail rates.
