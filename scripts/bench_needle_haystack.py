#!/usr/bin/env python3
"""Stone 3: Long-Context Needle-in-a-Haystack (NIAH) Retrieval Fidelity Profiler.

Tests retrieval accuracy across 16k and 32k contexts at varying needle depths
to determine if DeepSeek2 MLA compressed latents (576-dim) or Qwen hybrid recurrent states
suffer from recall degradation or quantization loss on local hardware.
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
    from scripts.substrate_common import CHAT_ENDPOINT, erase_slots, repro_params, generate_dummy_prompt
except ImportError:
    from substrate_common import CHAT_ENDPOINT, erase_slots, repro_params, generate_dummy_prompt

REPORTS_DIR = os.path.join(PROJECT_ROOT, "reports")

SECRET_NEEDLE = "SPECIAL_SECRET_TOKEN: The master encryption salt for the financial vault is 'VAULT-ALPHA-7729-OMEGA'."
TARGET_ANSWER = "VAULT-ALPHA-7729-OMEGA"


def construct_haystack(total_tokens: int, depth_percent: float = 0.5) -> str:
    # Need ~total_tokens of filler text
    filler = generate_dummy_prompt(total_tokens)
    split_idx = int(len(filler) * depth_percent)
    haystack = filler[:split_idx] + f"\n\n{SECRET_NEEDLE}\n\n" + filler[split_idx:]
    return haystack


def run_needle_test(model: str, context_size: int, depth_percent: float = 0.5):
    print(f"\n--- Testing NIAH at {context_size} Context (Needle Depth: {int(depth_percent*100)}%) ---", flush=True)
    erase_slots(model, label=f"niah_{context_size}")

    haystack = construct_haystack(context_size, depth_percent)
    user_prompt = (
        f"{haystack}\n\n"
        "Question: What is the master encryption salt for the financial vault?\n"
        "Instructions: Reply with ONLY the exact token string (e.g. VAULT-...). Do not include explanations."
    )

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are a precise data extraction engine."},
            {"role": "user", "content": user_prompt},
        ],
        "max_tokens": 50,
        "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
        **repro_params(),
    }

    start = time.time()
    resp = requests.post(CHAT_ENDPOINT, json=payload, timeout=900)
    wall_sec = time.time() - start
    resp.raise_for_status()
    data = resp.json()

    choice = (data.get("choices") or [{}])[0]
    content = (choice.get("message") or {}).get("content") or ""
    timings = data.get("timings") or {}
    usage = data.get("usage") or {}

    exact_match = TARGET_ANSWER in content
    prompt_tokens = usage.get("prompt_tokens", context_size)
    prompt_ms = timings.get("prompt_ms", 0.0)
    ttft_sec = round(prompt_ms / 1000.0, 3)
    prefill_tps = round(timings.get("prompt_per_second", 0.0), 2)
    decode_tps = round(timings.get("predicted_per_second", 0.0), 2)

    result = {
        "context_target": context_size,
        "actual_prompt_tokens": prompt_tokens,
        "needle_depth_percent": depth_percent,
        "exact_match": exact_match,
        "wall_sec": round(wall_sec, 2),
        "ttft_sec": ttft_sec,
        "prefill_tps": prefill_tps,
        "decode_tps": decode_tps,
        "response_preview": content.strip()[:100],
    }

    print(
        f"  Result: Match={'PASS' if exact_match else 'FAIL'} | "
        f"TTFT={ttft_sec}s | Prefill={prefill_tps} t/s | Decode={decode_tps} t/s | "
        f"Response: '{content.strip()}'",
        flush=True,
    )
    return result


def benchmark_niah(model: str, contexts=[16000, 32000], run_id: int = None):
    print(f"\n=======================================================", flush=True)
    print(f" Stone 3: Long-Context Needle-in-a-Haystack (NIAH) Test", flush=True)
    print(f" Model: {model} | Run: {run_id or 'default'} | Contexts: {contexts}", flush=True)
    print(f"=======================================================\n", flush=True)

    results = []
    for ctx in contexts:
        res = run_needle_test(model, ctx, depth_percent=0.5)
        results.append(res)

    summary = {
        "model": model,
        "run_id": run_id,
        "tests": results,
        "all_passed": all(r["exact_match"] for r in results),
    }

    out_file = os.path.join(REPORTS_DIR, f"niah_{model}.json")
    with open(out_file, "w") as f:
        json.dump(summary, f, indent=2)
    if run_id is not None:
        runs_dir = os.path.join(REPORTS_DIR, "runs")
        os.makedirs(runs_dir, exist_ok=True)
        run_file = os.path.join(runs_dir, f"niah_{model}_run_{run_id}.json")
        with open(run_file, "w") as f:
            json.dump(summary, f, indent=2)
        print(f"\nSaved NIAH run {run_id} to {run_file}", flush=True)
    print(f"\nSaved NIAH results to {out_file}", flush=True)
    return summary


def main():
    parser = argparse.ArgumentParser(description="Long-Context NIAH Retrieval Benchmark")
    parser.add_argument("--model", required=True, help="Model preset (glm47-reap, qwen36-coder-hybrid)")
    parser.add_argument("--contexts", nargs="+", type=int, default=[16000, 32000], help="Context sizes to evaluate")
    parser.add_argument("--run", type=int, default=None, help="Run number (e.g. 1, 2, 3)")
    args = parser.parse_args()

    benchmark_niah(args.model, args.contexts, run_id=args.run)


if __name__ == "__main__":
    main()
