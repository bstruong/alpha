---
repo: /home/user/Projects/berserker
---

# Architecture Plan: Validation Suite (v2 TDD)

## Global Constraints
* Use only Python 3 Standard Library for the runner and Python modules.
* You must pass `ruff check validation_v2/` and `pyright validation_v2/` before declaring success.
* Do not modify immutable test files (`test_*.py`); write implementation code until tests pass.
* No brittle transpilation (`sed` on code is strictly forbidden). Use native toolchains.
* No empty stub functions or mock logic (e.g., empty `main()` in Go is forbidden).

## Tasks

### T01 — Robust Memory Soak Monitor
```task
id: T01
phase: 1
depends: []
write: ["validation_v2/soak.py"]
read: ["validation_v2/test_soak.py"]
acceptance: "python3 validation_v2/test_soak.py && ruff check validation_v2/soak.py"
max_output_tokens: 1500
attempts: 5
```
Implement `validation_v2/soak.py` with `calculate_drift(start_free_mb: float, end_free_mb: float) -> float`.
Must accurately calculate swap drift: positive drift means swap usage increased (leak), negative drift means swap usage decreased (freed).

### T02 — True Streaming Performance & Token Metrics
```task
id: T02
phase: 2
depends: [T01]
write: ["validation_v2/perf.py"]
read: ["validation_v2/test_perf.py"]
acceptance: "python3 validation_v2/test_perf.py && ruff check validation_v2/perf.py && pyright validation_v2/"
max_output_tokens: 2500
attempts: 5
```
Implement `validation_v2/perf.py` with `measure_streaming_ttft(prompt: str, url: str = "http://127.0.0.1:8080/v1/chat/completions", system: str = "") -> dict`.
Requirements:
1. Connect via `urllib.request` using POST and `"stream": True` in JSON payload.
2. Parse Server-Sent Events (SSE) stream line-by-line (`data: ...`).
3. Record exact TTFT (`time.perf_counter() - start_time`) upon receiving the first chunk containing delta content or reasoning.
4. Accumulate streamed tokens and text content until `data: [DONE]`.
5. Return dict with keys: `ttft_s`, `total_time_s`, `token_count`, `content`, `toks_per_s`.

### T03 — Polyglot Code Quality Harness Tasks
```task
id: T03
phase: 3
depends: [T01]
write: ["validation_v2/tasks/go-merge-intervals/main.go", "validation_v2/tasks/go-merge-intervals/test.sh", "validation_v2/tasks/ts-semver-compare/semver.ts", "validation_v2/tasks/ts-semver-compare/test.sh", "validation_v2/tasks/python-token-bucket/token_bucket.py", "validation_v2/tasks/python-token-bucket/test.sh", "validation_v2/tasks/java-lru-cache/LRUCache.java", "validation_v2/tasks/java-lru-cache/test.sh"]
read: []
acceptance: "bash validation_v2/tasks/go-merge-intervals/test.sh && bash validation_v2/tasks/ts-semver-compare/test.sh && bash validation_v2/tasks/python-token-bucket/test.sh && bash validation_v2/tasks/java-lru-cache/test.sh"
max_output_tokens: 3000
attempts: 5
```
Implement polyglot tasks with real validations:
1. `go-merge-intervals`: Real interval merge logic. `main()` must execute test assertions (e.g. panic if incorrect). `test.sh` runs `go run main.go`.
2. `ts-semver-compare`: TypeScript compareSemver function with assertions. `test.sh` executes via `node --experimental-strip-types semver.ts` (ZERO `sed` regexes).
3. `python-token-bucket`: Token bucket rate limiter with assertions. `test.sh` runs `python3 token_bucket.py`.
4. `java-lru-cache`: Java LRU cache with `-ea` assertions. `test.sh` compiles and runs `java -ea LRUCache`.

### T04 — Unified CLI Runner & Benchmark Execution
```task
id: T04
phase: 4
depends: [T01, T02, T03]
write: ["validation_v2/run_suite.py"]
read: ["validation_v2/soak.py", "validation_v2/perf.py"]
acceptance: "python3 validation_v2/run_suite.py all --duration 5 && ruff check validation_v2/run_suite.py && pyright validation_v2/"
max_output_tokens: 3000
attempts: 5
```
Implement `validation_v2/run_suite.py` CLI runner with subcommands `perf`, `soak`, `quality`, and `all`.
Requirements:
1. Fix the argparse bug: `all` must pass valid default attributes (e.g. `dry_run=False`, `duration=30`) so it does not crash on missing flags.
2. Incorporate `validation_v2/perf.py` for true streaming TTFT and throughput.
3. Incorporate `validation_v2/soak.py` for leak detection using `calculate_drift`.
4. Run polyglot tasks in `validation_v2/tasks/`.
5. Save metrics to `validation_v2/results/<timestamp>/metrics.json`.
