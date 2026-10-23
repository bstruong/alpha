#!/usr/bin/env python3
"""Benchmark B: Multi-Turn Agent Prefix Cache Profiler (Turn 1 to Turn 10).

Simulates an interactive agent session across 10 progressive turns without erasing slots,
measuring Cold TTFT (Turn 1) vs Warm TTFT (Turns 2-10), cache hit ratio, and prefix reuse
efficiency on:
  - glm47-reap (DeepSeek2 MLA pure attention KV shifting)
  - qwen36-coder-hybrid (Hybrid MoE recurrent state checkpoints)
"""
import argparse
import json
import os
import sys
import time
try:
    import requests
except ImportError:
    requests = None

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

try:
    from scripts.substrate_common import CHAT_ENDPOINT, erase_slots, repro_params
except ImportError:
    from substrate_common import CHAT_ENDPOINT, erase_slots, repro_params

REPORTS_DIR = os.path.join(PROJECT_ROOT, "reports")

AGENT_SYSTEM_PROMPT = """You are an expert autonomous software engineer working on a high-throughput financial microservice.
Follow these engineering guidelines strictly:
1. Production-grade Python 3.12+ with strict typing (PEP 484/526), TypedDict, and Pydantic v2 schemas.
2. Asynchronous concurrency using asyncio and asyncpg for non-blocking I/O.
3. Resilience patterns: Circuit breaker, exponential backoff with jitter, dead-letter queues.
4. Observability: OpenTelemetry spans, Prometheus metrics (histograms for latency, counters for errors).
5. Clean Architecture: Strict decoupling between Domain Entities, Use Cases, Repositories, and HTTP Controllers.
6. Provide concise, production-ready code with complete type annotations and docstrings.
"""

TURNS_PROMPTS = [
    # Turn 1
    "Design and implement the core `PostgresConnectionManager` class with connection validation and lifecycle hooks.",
    # Turn 2
    "Add an asynchronous connection pool with min_size=5, max_size=50, and exponential backoff retry logic on acquisition timeout.",
    # Turn 3
    "Instrument the connection pool with Prometheus metrics: active_connections gauge, acquisition_latency histogram, and checkout_errors counter.",
    # Turn 4
    "Implement read/write splitting: route SELECT queries to a read-replica pool and INSERT/UPDATE/DELETE queries to the primary master pool.",
    # Turn 5
    "Refactor the manager to provide an asynchronous context manager `@asynccontextmanager async def transaction()` with automatic commit and rollback.",
    # Turn 6
    "Write a complete pytest-asyncio unit and integration test suite with mock connection fixtures testing transaction rollbacks on OperationalError.",
    # Turn 7
    "Add a distributed Redis lock wrapper `with_distributed_lock(key, ttl=10)` to prevent concurrent schema migrations across multiple replicas.",
    # Turn 8
    "Implement an HTTP `/health/db` endpoint handler returning JSON with pool saturation ratio, average query latency, and replica sync lag.",
    # Turn 9
    "Add strict parameterized query validation to forbid raw SQL string interpolation and enforce AST-level validation on queries.",
    # Turn 10
    "Perform a final production audit: optimize memory footprint, add complete PEP 257 docstrings, and handle graceful shutdown on SIGTERM.",
]


def run_prefix_cache_benchmark(model: str):
    print(f"\n=======================================================", flush=True)
    print(f" Multi-Turn Prefix Cache Benchmark for Model: {model}", flush=True)
    print(f" Simulating 10-turn progressive agent conversation...", flush=True)
    print(f"=======================================================\n", flush=True)

    # Clean slot initialization before Turn 1
    erase_slots(model, label="prefix_cache_init")

    conversation = [{"role": "system", "content": AGENT_SYSTEM_PROMPT}]
    turn_metrics = []

    for turn_num, user_prompt in enumerate(TURNS_PROMPTS, start=1):
        print(f"\n>>> Turn {turn_num}/10 <<<", flush=True)
        print(f"  User: {user_prompt[:70]}...", flush=True)

        conversation.append({"role": "user", "content": user_prompt})

        payload = {
            "model": model,
            "messages": conversation,
            "max_tokens": 200,
            "stream": False,
            "chat_template_kwargs": {"enable_thinking": False},
            **repro_params(cache_prompt=True),
        }

        start_time = time.time()
        resp = requests.post(CHAT_ENDPOINT, json=payload, timeout=600)
        wall_sec = time.time() - start_time
        resp.raise_for_status()
        data = resp.json()

        choice = (data.get("choices") or [{}])[0]
        assistant_content = (choice.get("message") or {}).get("content") or ""
        conversation.append({"role": "assistant", "content": assistant_content})

        usage = data.get("usage") or {}
        details = usage.get("prompt_tokens_details") or {}
        timings = data.get("timings") or {}

        prompt_tokens = usage.get("prompt_tokens", 0)
        cached_tokens = details.get("cached_tokens") or timings.get("cache_n", 0)
        completion_tokens = usage.get("completion_tokens", 0)

        prompt_eval_ms = timings.get("prompt_ms", 0.0)
        prompt_tps = timings.get("prompt_per_second", 0.0)
        decode_tps = timings.get("predicted_per_second", 0.0)

        # Warm TTFT is prompt eval time (latency before first token generation)
        ttft_sec = round(prompt_eval_ms / 1000.0, 3)
        cache_ratio = round((cached_tokens / prompt_tokens * 100), 1) if prompt_tokens > 0 else 0.0

        record = {
            "turn": turn_num,
            "wall_sec": round(wall_sec, 3),
            "ttft_sec": ttft_sec,
            "prompt_tokens": prompt_tokens,
            "cached_tokens": cached_tokens,
            "cache_hit_percent": cache_ratio,
            "new_prompt_tokens": max(0, prompt_tokens - cached_tokens),
            "completion_tokens": completion_tokens,
            "prompt_throughput_tps": round(prompt_tps, 2),
            "decode_throughput_tps": round(decode_tps, 2),
            "assistant_preview": assistant_content[:150].replace("\n", " ") + "...",
        }
        turn_metrics.append(record)

        print(
            f"  Result: TTFT={ttft_sec}s | Prompt={prompt_tokens} (Cached: {cached_tokens} = {cache_ratio}%) | "
            f"Decode={decode_tps:.1f} t/s | Wall={wall_sec:.2f}s",
            flush=True,
        )

    summary = {
        "model": model,
        "turns_count": len(turn_metrics),
        "cold_ttft_sec": turn_metrics[0]["ttft_sec"],
        "avg_warm_ttft_sec": round(sum(m["ttft_sec"] for m in turn_metrics[1:]) / len(turn_metrics[1:]), 3),
        "final_context_tokens": turn_metrics[-1]["prompt_tokens"],
        "final_cache_ratio": turn_metrics[-1]["cache_hit_percent"],
        "turns": turn_metrics,
    }

    return summary


def main():
    parser = argparse.ArgumentParser(description="Multi-Turn Prefix Cache Profiler")
    parser.add_argument("--model", required=True, help="Model preset (glm47-reap, qwen36-coder-hybrid)")
    args = parser.parse_args()

    results = run_prefix_cache_benchmark(args.model)
    os.makedirs(REPORTS_DIR, exist_ok=True)
    out_file = os.path.join(REPORTS_DIR, f"prefix_cache_{args.model}.json")
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nSaved prefix cache results to {out_file}", flush=True)


if __name__ == "__main__":
    main()
