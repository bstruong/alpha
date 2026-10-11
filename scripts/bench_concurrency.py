#!/usr/bin/env python3
"""Stone 1: Dual-Slot Simultaneous Concurrency Profiler (parallel = 2).

Sends simultaneous, concurrent requests to Slot 0 and Slot 1 at the exact same millisecond,
measuring TTFT jitter, per-slot decode throughput, and aggregate DDR5 memory bandwidth.
"""
import argparse
import concurrent.futures
import json
import os
import sys
import time
import requests

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from tests.benchmark_suite.common import CHAT_ENDPOINT, erase_slots, repro_params
from tests.benchmark_suite.telemetry.test_hardware_limits import generate_dummy_prompt

REPORTS_DIR = os.path.join(PROJECT_ROOT, "reports")


def send_inference(model: str, slot_label: str, prompt_tokens: int, max_tokens: int):
    prompt_text = generate_dummy_prompt(prompt_tokens)
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are a concise engineering assistant."},
            {"role": "user", "content": f"Summarize and analyze the following technical documentation:\n{prompt_text}\nAnalysis:"},
        ],
        "max_tokens": max_tokens,
        "stream": True,
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
        **repro_params(),
    }

    start_time = time.time()
    ttft = None
    tokens_generated = 0

    response = requests.post(CHAT_ENDPOINT, json=payload, stream=True, timeout=300)
    response.raise_for_status()

    for line in response.iter_lines(decode_unicode=True):
        if not line:
            continue
        if ttft is None:
            ttft = time.time() - start_time
        if line.startswith("data: "):
            data = line[6:].strip()
            if data and data != "[DONE]":
                try:
                    chunk = json.loads(data)
                    usage = chunk.get("usage") or {}
                    if usage.get("completion_tokens"):
                        tokens_generated = int(usage["completion_tokens"])
                except json.JSONDecodeError:
                    pass

    total_wall = time.time() - start_time
    decode_time = total_wall - ttft if ttft else 0
    decode_tps = tokens_generated / decode_time if decode_time > 0 else 0

    return {
        "slot": slot_label,
        "wall_sec": round(total_wall, 3),
        "ttft_sec": round(ttft, 3) if ttft else None,
        "tokens_generated": tokens_generated,
        "decode_throughput_tps": round(decode_tps, 2),
    }


def benchmark_concurrency(model: str, prompt_tokens: int = 1000, max_tokens: int = 150, run_id: int = None):
    print(f"\n=======================================================", flush=True)
    print(f" Stone 1: Dual-Slot Simultaneous Concurrency Benchmark", flush=True)
    print(f" Model: {model} | Run: {run_id or 'default'} | Slots: 2 Concurrent | Target: {max_tokens} tokens", flush=True)
    print(f"=======================================================\n", flush=True)

    erase_slots(model, label="concurrency_init")

    # Step 1: Baseline Single-Slot Execution
    print(">>> 1. Baseline: Single-Slot Execution (Solo) <<<", flush=True)
    solo_res = send_inference(model, "Slot_Solo", prompt_tokens, max_tokens)
    print(f"  Solo Result: TTFT={solo_res['ttft_sec']}s, Decode={solo_res['decode_throughput_tps']} t/s, Wall={solo_res['wall_sec']}s\n", flush=True)

    erase_slots(model, label="before_dual_slot")
    time.sleep(1)

    # Step 2: Simultaneous Dual-Slot Execution
    print(">>> 2. Dual-Slot Execution (Slot 0 and Slot 1 Fired Simultaneously) <<<", flush=True)
    overall_start = time.time()

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        f0 = executor.submit(send_inference, model, "Slot_0", prompt_tokens, max_tokens)
        f1 = executor.submit(send_inference, model, "Slot_1", prompt_tokens, max_tokens)
        res_0 = f0.result()
        res_1 = f1.result()

    overall_wall = time.time() - overall_start
    total_tokens = res_0["tokens_generated"] + res_1["tokens_generated"]
    aggregate_tps = round(total_tokens / overall_wall, 2)

    print(f"  Slot 0: TTFT={res_0['ttft_sec']}s, Decode={res_0['decode_throughput_tps']} t/s, Wall={res_0['wall_sec']}s", flush=True)
    print(f"  Slot 1: TTFT={res_1['ttft_sec']}s, Decode={res_1['decode_throughput_tps']} t/s, Wall={res_1['wall_sec']}s", flush=True)
    print(f"  Aggregate Dual-Slot Throughput: {aggregate_tps} tok/s (across both slots in {overall_wall:.2f}s)\n", flush=True)

    summary = {
        "model": model,
        "run_id": run_id,
        "single_slot_baseline": solo_res,
        "dual_slot_concurrent": {
            "overall_wall_sec": round(overall_wall, 3),
            "aggregate_throughput_tps": aggregate_tps,
            "slot_0": res_0,
            "slot_1": res_1,
            "concurrency_efficiency_ratio": round(aggregate_tps / solo_res["decode_throughput_tps"], 2) if solo_res["decode_throughput_tps"] > 0 else 1.0,
        }
    }

    out_file = os.path.join(REPORTS_DIR, f"concurrency_{model}.json")
    with open(out_file, "w") as f:
        json.dump(summary, f, indent=2)
    if run_id is not None:
        runs_dir = os.path.join(REPORTS_DIR, "runs")
        os.makedirs(runs_dir, exist_ok=True)
        run_file = os.path.join(runs_dir, f"concurrency_{model}_run_{run_id}.json")
        with open(run_file, "w") as f:
            json.dump(summary, f, indent=2)
        print(f"Saved concurrency benchmark run {run_id} to {run_file}", flush=True)
    print(f"Saved concurrency benchmark to {out_file}", flush=True)
    return summary


def main():
    parser = argparse.ArgumentParser(description="Dual-Slot Concurrency Benchmark")
    parser.add_argument("--model", required=True, help="Model preset (glm47-reap, qwen36-coder-hybrid)")
    parser.add_argument("--run", type=int, default=None, help="Run number (e.g. 1, 2, 3)")
    args = parser.parse_args()

    benchmark_concurrency(args.model, run_id=args.run)


if __name__ == "__main__":
    main()
