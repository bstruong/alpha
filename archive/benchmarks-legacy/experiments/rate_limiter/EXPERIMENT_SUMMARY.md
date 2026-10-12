# Rate Limiter Benchmark & Local LLM Telemetry Experiment Summary

This report documents the findings and telemetry from benchmarking the local LLM inference stack (`llama-server` running `qwen3.6-35b-a3b-q4_k_m.gguf`) against Python TokenBucket rate limiter implementations, comparing an unconstrained architectural generation prompt against a bounded, test-driven fix.

---

## 1. Executive Summary

During evaluation of local agentic code generation for high-concurrency systems, two distinct execution strategies were benchmarked:

1. **Unbounded Architectural Generation (`run_python_benchmark.py`):** An unconstrained prompt requesting a full, production-ready TokenBucket rate limiter with Redis fallback, concurrency locks, clock-skew mitigation, and pytest suites. This triggered a catastrophic **infinite reasoning loop**, consuming **12,288 tokens** over **280.38 seconds** of compute without emitting a single byte of usable code.
2. **Bounded Test-Driven Generation (`run_bounded_benchmark.py`):** A scoped prompt isolating the atomic `allow` method to satisfy a pre-defined clock-skew pytest fixture with `enable_thinking: False`. This completed successfully in **5.93 seconds**, producing **224 chunks (223 predicted tokens)** of verified, passing Python code.

Across both runs, the local workstation hardware demonstrated steady decode throughput of **~38–44 tokens/s**, confirming that local inference has ample speed for interactive agentic development, provided that runaway reasoning loops are guarded against.

---

## 2. Side-by-Side Telemetry Comparison

Data extracted from `qwen_benchmark_metrics.json` and `bounded_metrics.json`:

| Telemetry Metric | Run 1: Unbounded Generation (`qwen_benchmark_metrics.json`) | Run 2: Bounded Fix (`bounded_metrics.json`) | Delta / Improvement |
| :--- | :---: | :---: | :---: |
| **Total Wall Time** | 280.38 s (~4.67 min) | 5.93 s | **97.89% reduction** (47.3x faster) |
| **Time to First Token (TTFT)** | 1.253 s (1,252.8 ms) | 0.113 s (112.8 ms) | **90.99% reduction** (11.1x faster) |
| **Predicted / Generated Tokens** | 12,288 tokens (hit ceiling) | 223 tokens | **98.19% reduction** |
| **Total Streaming Chunks** | 12,290 chunks | 224 chunks | Bounded output stream |
| **Reasoning Content Length** | 40,171 chars | 0 chars | Thinking disabled |
| **Final Content Length** | 0 chars (empty payload) | 997 chars | Full working implementation |
| **Decode Throughput** | 44.02 tokens/s | 38.18 tokens/s | **~38–44 tokens/s** steady hardware rate |
| **Prefill / Prompt Speed** | 277.12 tokens/s (236 prompt tokens) | 39.96 tokens/s (4 prompt + 276 cached) | Effective KV cache reuse |
| **Pytest Verification** | N/A (no code output produced) | **PASSED (100%, 1 test in 0.00s)** | Hermetic validation successful |

---

## 3. The "Infinite Reasoning Loop" Failure Mode

### Observations & Telemetry
In Run 1, the model was given an open-ended specification requiring:
- In-memory token bucket with per-bucket `threading.Lock`
- Secondary `RedisLimiter` with atomic Lua scripts querying server time
- Edge cases: monotonic clock skew handling, input validation, LRU eviction
- Pytest suite for burst capacity, refill intervals, and thread safety

The telemetry in `qwen_benchmark_metrics.json` revealed severe runaway behavior:
* **Generation Wall Time:** 280.38 seconds (279.13 seconds in decode evaluation).
* **Token Exhaustion:** Exactly **12,288 tokens** (`predicted_n: 12288`), which matched the configured `max_tokens` ceiling.
* **Zero Output Code:** `content_length_chars: 0` and `qwen_rate_limiter_output.txt` remained completely empty (0 bytes).
* **Runaway Reasoning:** `reasoning_length_chars: 40171` recorded in `qwen_reasoning.txt`.

### Root Cause Analysis
Modern reasoning/thinking LLMs equipped with chain-of-thought capabilities can enter recursive meta-planning loops when presented with multi-tier architectural prompts. The model repeatedly analyzed:
1. Lock granularity and lock-striping memory overhead.
2. Time precision nuances between `time.time()`, `time.monotonic()`, and Redis `TIME` command.
3. Lua table unpacking edge cases in Redis cluster vs standalone nodes.
4. Pytest fixture mocking strategies for multithreading.

Because the prompt did not constrain reasoning depth or mandate an immediate code block structure, the model continually deferred closing its thinking block (`</think>`), until it abruptly hit the 12,288-token generation ceiling and halted without producing the actual solution.

---

## 4. The Bounded Fix & Sub-6s Resolution

### Strategy
To overcome the reasoning loop, the harness in `run_bounded_benchmark.py` introduced three structural constraints:
1. **Scoped Prompting:** Narrowed the objective strictly to implementing the internal logic of `allow(cost: float) -> bool` inside an existing `TokenBucket` class skeleton, explicitly barring fallback architecture or extra tests.
2. **Explicit Verification Target:** Supplied the exact `pytest` test case (`test_clock_skew_preserves_baseline`) that the implementation was required to satisfy.
3. **Disabled Thinking Guardrail:** Set `"chat_template_kwargs": {"enable_thinking": False}` in the chat completions payload.

### Results & Verification
The bounded approach achieved dramatic efficiency gains:
* **Wall Time:** Dropped from **280.4s down to 5.93s** (5.81s decode time).
* **Token Count:** Generated exactly **223 tokens** across **224 chunks** (997 characters of code).
* **Latency:** TTFT dropped to **112.8 ms**.
* **Correctness:** The generated code (`generated_token_bucket.py`) correctly preserved the `_last_refill` timestamp invariant when system time moved backward (`now < self._last_refill`), passing the hermetic pytest check instantly (`pytest_exit_code: 0`, 1 passed in 0.00s).

```python
# Generated internal logic for allow():
with self._lock:
    now = time.monotonic()
    
    # Only add tokens if current time is greater than or equal to last refill time
    if now >= self._last_refill:
        elapsed = now - self._last_refill
        new_tokens = elapsed * self.refill_rate
        self.tokens = min(self.max_tokens, self.tokens + new_tokens)
        self._last_refill = now
    
    # Check if we have enough tokens
    if self.tokens >= cost:
        self.tokens -= cost
        return True
    else:
        return False
```

---

## 5. Hardware Throughput & Local Inference Viability

### Telemetry Benchmarks
* **Hardware & Runtime:** Local workstation running CachyOS Linux with AMD Radeon GPU acceleration and `llama-server`.
* **Model:** `qwen3.6-35b-a3b-q4_k_m.gguf` (35B active parameter architecture, Q4_K_M quantization).
* **Generation Throughput:** 
  * Unbounded Run: **44.02 tokens/s** (`predicted_ms: 279125.334`, `predicted_n: 12288`).
  * Bounded Run: **38.18 tokens/s** (`predicted_ms: 5814.323`, `predicted_n: 223`).
  * Combined Hardware Envelope: **~38–44 tokens/s**.
* **Prefill Throughput:**
  * Cold evaluation: **277.12 tokens/s** (236 tokens in 851.6 ms).
  * Prompt cache hit: **39.96 tokens/s** (276 tokens cached, 4 tokens processed in 100.1 ms).

### Evaluation
A generation speed of ~38–44 tokens/s provides sub-second latency for typical code completions and function-level patches. At this throughput, interactive development and agentic feedback loops remain exceptionally responsive, provided prompts do not trigger unbounded reasoning loops.

---

## 6. Key Lessons & Engineering Guidelines

1. **Guard Against Unbounded Reasoning:**
   * Open-ended architectural prompts sent to reasoning models without strict token budgets or explicit thinking suppression can exhaust large context buffers (12k+ tokens) in unproductive loops.
   * For deterministic implementation tasks, disable reasoning (`enable_thinking: False`) or enforce strict `reasoning_budget` / `max_tokens` boundaries.

2. **Decompose Complex Architecture into Bounded Atomic Tasks:**
   * Rather than asking a local model to design, implement, and test an entire distributed system in a single inference call, decompose tasks into discrete atomic components (e.g., class scaffold -> method implementation -> test execution).

3. **Incorporate Test-Driven Feedback Loops:**
   * Providing the target test contract directly in the prompt yields concise, compliant implementations in seconds.
   * Combining local LLM generation with immediate sub-process test execution (`pytest`) provides deterministic verification with minimal overhead.

4. **Production Architecture Reference:**
   * The complete, audited reference implementation of the thread-safe `TokenBucketLimiter`, `RedisLimiter` with atomic Lua scripts, LRU cache eviction, and fallback orchestrator is archived in `experiments/rate_limiter/rate_limiter.py` alongside the complete concurrency test suite in `experiments/rate_limiter/test_rate_limiter.py`.
