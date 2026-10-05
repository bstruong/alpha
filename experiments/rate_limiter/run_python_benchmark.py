import urllib.request
import json
import time
import os
import sys

PROMPT = """Write a complete, production-ready TokenBucket Rate Limiter in Python with a secondary Redis fallback.

Requirements:
1. Core Implementation: In-memory token bucket using `threading.Lock` for per-bucket synchronization to avoid global lock contention.
2. Interface: A primary class with `allow(key: str, cost: float) -> bool` and `reset(key: str)`.
3. Distributed Fallback: A `RedisLimiter` class using `redis-py` and an atomic Lua script. Query Redis server time directly inside the Lua script to prevent client-side distributed clock skew.
4. Edge Cases:
   - Raise explicit exceptions (e.g., `ValueError`) for invalid constraints like cost <= 0 or max_tokens <= 0.
   - Handle system clock skew safely without corrupting bucket refill math.
   - Implement TTL or LRU eviction for the in-memory buckets to prevent OOM errors from high-cardinality keys.
5. Testing: A complete `pytest` suite verifying burst capacity, temporal refill intervals, thread safety under concurrent load, and reset behavior."""

def main():
    payload = {
        "model": "./models/qwen3.6-35b-a3b-q4_k_m.gguf",
        "messages": [
            {"role": "user", "content": PROMPT}
        ],
        "temperature": 0.2,
        "max_tokens": 12288,
        "stream": True
    }

    req = urllib.request.Request(
        "http://localhost:8080/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    print("[BENCHMARK] Dispatching Python Rate Limiter prompt to http://localhost:8080/v1/chat/completions...", flush=True)
    t0 = time.perf_counter()
    first_token_time = None
    total_chunks = 0

    accumulated_content = []
    accumulated_reasoning = []
    final_timings = None

    with urllib.request.urlopen(req) as resp:
        for raw_line in resp:
            line = raw_line.decode("utf-8").strip()
            if not line.startswith("data: "):
                continue
            data_str = line[6:].strip()
            if data_str == "[DONE]":
                break
            try:
                chunk = json.loads(data_str)
            except Exception:
                continue

            choices = chunk.get("choices", [])
            if choices:
                delta = choices[0].get("delta", {})
                content = delta.get("content", "")
                reasoning = delta.get("reasoning_content", "")

                if (content or reasoning) and first_token_time is None:
                    first_token_time = time.perf_counter()

                if content:
                    accumulated_content.append(content)
                if reasoning:
                    accumulated_reasoning.append(reasoning)

            total_chunks += 1
            if total_chunks % 500 == 0:
                elapsed = time.perf_counter() - t0
                print(f"  [STREAM] {total_chunks} chunks received ({elapsed:.1f}s elapsed)...", flush=True)

            if "timings" in chunk:
                final_timings = chunk["timings"]

    t_end = time.perf_counter()
    total_elapsed = t_end - t0
    ttft = (first_token_time - t0) if first_token_time else 0.0

    full_content = "".join(accumulated_content)
    full_reasoning = "".join(accumulated_reasoning)

    output_dir = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(output_dir, "qwen_rate_limiter_output.txt"), "w", encoding="utf-8") as f:
        f.write(full_content)
    with open(os.path.join(output_dir, "qwen_reasoning.txt"), "w", encoding="utf-8") as f:
        f.write(full_reasoning)

    results = {
        "wall_time_total_s": total_elapsed,
        "ttft_s": ttft,
        "content_length_chars": len(full_content),
        "reasoning_length_chars": len(full_reasoning),
        "total_chunks": total_chunks,
        "timings": final_timings
    }

    with open(os.path.join(output_dir, "qwen_benchmark_metrics.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    print("\n[BENCHMARK COMPLETED]", flush=True)
    print(f"Total Wall Time: {total_elapsed:.3f} s", flush=True)
    print(f"Time To First Token (TTFT): {ttft:.3f} s ({ttft*1000:.1f} ms)", flush=True)
    if final_timings:
        print(f"Prompt Tokens: {final_timings.get('prompt_n')}", flush=True)
        print(f"Prompt Eval Time: {final_timings.get('prompt_ms'):.1f} ms", flush=True)
        print(f"Prefill Speed: {final_timings.get('prompt_per_second'):.2f} tokens/s", flush=True)
        print(f"Predicted Tokens: {final_timings.get('predicted_n')}", flush=True)
        print(f"Predicted Eval Time: {final_timings.get('predicted_ms'):.1f} ms", flush=True)
        print(f"Decode / Generation Speed: {final_timings.get('predicted_per_second'):.2f} tokens/s", flush=True)

if __name__ == "__main__":
    main()
