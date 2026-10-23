#!/usr/bin/env python3
"""Benchmark A: Homelab Memory Contention & Swap Thrashing Profiler.

Simulates background container memory usage (e.g. 0GB baseline, 4GB, and 6GB dirty memory)
and measures TTFT, decode throughput, swap delta, and page pressure on:
  - glm47-reap
  - qwen36-coder-hybrid
"""
import argparse
import gc
import json
import os
import subprocess
import sys
import time
try:
    import requests
except ImportError:
    requests = None

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

try:
    from scripts.substrate_common import BASE_URL, CHAT_ENDPOINT, erase_slots, repro_params, generate_dummy_prompt, get_ram_usage, get_vram_usage
except ImportError:
    from substrate_common import BASE_URL, CHAT_ENDPOINT, erase_slots, repro_params, generate_dummy_prompt, get_ram_usage, get_vram_usage

REPORTS_DIR = os.path.join(PROJECT_ROOT, "reports")


def get_meminfo():
    with open("/proc/meminfo") as f:
        m = {line.split(":")[0].strip(): int(line.split(":")[1].split()[0]) for line in f}
    return {
        "mem_total_mb": round(m.get("MemTotal", 0) / 1024, 2),
        "mem_avail_mb": round(m.get("MemAvailable", 0) / 1024, 2),
        "swap_total_mb": round(m.get("SwapTotal", 0) / 1024, 2),
        "swap_free_mb": round(m.get("SwapFree", 0) / 1024, 2),
        "swap_used_mb": round((m.get("SwapTotal", 0) - m.get("SwapFree", 0)) / 1024, 2),
    }


def allocate_dirty_memory(gb: float):
    if gb <= 0:
        return None
    print(f"  [Memory Pressure] Allocating and dirtying {gb:.1f} GB host RAM...", flush=True)
    size_bytes = int(gb * 1024 * 1024 * 1024)
    buf = bytearray(size_bytes)
    # Touch each page (4096-byte stride) to force real physical page allocation
    for i in range(0, size_bytes, 4096):
        buf[i] = 42
    print(f"  [Memory Pressure] {gb:.1f} GB buffer pinned in memory.", flush=True)
    return buf


def run_single_inference(model: str, size: int):
    prompt = generate_dummy_prompt(size)
    user_content = f"Summarize this text: {prompt}\n\nSummary:"
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are a concise assistant."},
            {"role": "user", "content": user_content},
        ],
        "max_tokens": 50,
        "stream": True,
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
        **repro_params(),
    }
    erase_slots(model, label=f"pressure_{size}")

    start_time = time.time()
    ttft = None
    tokens_generated = 0
    prompt_tokens_reported = None
    peak_ram = get_ram_usage()
    peak_vram = get_vram_usage()
    last_sample = start_time

    response = requests.post(CHAT_ENDPOINT, json=payload, stream=True, timeout=1800)
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
                    if usage.get("prompt_tokens"):
                        prompt_tokens_reported = int(usage["prompt_tokens"])
                except json.JSONDecodeError:
                    pass

        now = time.time()
        if now - last_sample >= 0.5:
            peak_ram = max(peak_ram, get_ram_usage())
            peak_vram = max(peak_vram, get_vram_usage())
            last_sample = now

    total_time = time.time() - start_time
    decode_time = total_time - ttft if ttft else 0
    decode_tps = tokens_generated / decode_time if decode_time > 0 else 0
    prefill_tps = size / ttft if ttft and ttft > 0 else 0

    return {
        "wall_sec": round(total_time, 3),
        "ttft_sec": round(ttft, 3) if ttft else None,
        "prefill_tps": round(prefill_tps, 2),
        "decode_tps": round(decode_tps, 2),
        "tokens_generated": tokens_generated,
        "prompt_tokens_reported": prompt_tokens_reported,
        "peak_ram_mb": round(peak_ram, 2),
        "peak_vram_mb": peak_vram,
    }


def benchmark_model_pressure(model: str, pressure_tiers=[0.0, 4.0, 6.0]):
    print(f"\n=======================================================", flush=True)
    print(f" Memory Pressure Benchmark for Model: {model}", flush=True)
    print(f" Pressure Tiers: {pressure_tiers} GB", flush=True)
    print(f"=======================================================\n", flush=True)

    tier_results = {}

    for tier_gb in pressure_tiers:
        tier_label = f"{int(tier_gb)}GB" if tier_gb > 0 else "Baseline_0GB"
        print(f"\n>>> Running Pressure Tier: {tier_label} <<<", flush=True)

        mem_before = get_meminfo()
        print(f"  Pre-test Host Memory: Avail={mem_before['mem_avail_mb']} MB, SwapUsed={mem_before['swap_used_mb']} MB", flush=True)

        buf = allocate_dirty_memory(tier_gb)
        try:
            mem_under_pressure = get_meminfo()
            print(f"  Under Pressure: Avail={mem_under_pressure['mem_avail_mb']} MB, SwapUsed={mem_under_pressure['swap_used_mb']} MB", flush=True)

            print("  Executing 2k context inference...", flush=True)
            res_2k = run_single_inference(model, 2000)
            print(f"  2k Result: TTFT={res_2k['ttft_sec']}s, Prefill={res_2k['prefill_tps']} t/s, Decode={res_2k['decode_tps']} t/s", flush=True)

            print("  Executing 8k context inference...", flush=True)
            res_8k = run_single_inference(model, 8000)
            print(f"  8k Result: TTFT={res_8k['ttft_sec']}s, Prefill={res_8k['prefill_tps']} t/s, Decode={res_8k['decode_tps']} t/s", flush=True)

            mem_after = get_meminfo()
            swap_spill_mb = round(mem_after["swap_used_mb"] - mem_before["swap_used_mb"], 2)

            tier_results[tier_label] = {
                "pressure_gb": tier_gb,
                "mem_before_test": mem_before,
                "mem_under_pressure": mem_under_pressure,
                "mem_after_test": mem_after,
                "swap_spill_mb": max(0.0, swap_spill_mb),
                "context_2k": res_2k,
                "context_8k": res_8k,
            }
        finally:
            if buf is not None:
                del buf
                gc.collect()
                print(f"  [Memory Pressure] Released {tier_gb:.1f} GB buffer.", flush=True)

        time.sleep(2)

    return tier_results


def main():
    parser = argparse.ArgumentParser(description="Homelab Memory Contention Benchmark")
    parser.add_argument("--model", required=True, help="Model preset (glm47-reap, qwen36-coder-hybrid)")
    parser.add_argument("--tiers", nargs="+", type=float, default=[0.0, 4.0, 6.0], help="Pressure tiers in GB")
    args = parser.parse_args()

    results = benchmark_model_pressure(args.model, args.tiers)
    os.makedirs(REPORTS_DIR, exist_ok=True)
    out_file = os.path.join(REPORTS_DIR, f"pressure_{args.model}.json")
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nSaved pressure results to {out_file}", flush=True)


if __name__ == "__main__":
    main()
