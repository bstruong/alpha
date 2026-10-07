import time
import requests
import subprocess
import json
import sys
import os

try:
    from tests.benchmark_suite.common import (
        BASE_URL,
        CHAT_ENDPOINT as ENDPOINT,
        FLASH_MODEL,
        erase_slots,
        repro_params,
    )
except ImportError:  # executed directly as a script
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
    from tests.benchmark_suite.common import (
        BASE_URL,
        CHAT_ENDPOINT as ENDPOINT,
        FLASH_MODEL,
        erase_slots,
        repro_params,
    )

TOKENIZE_ENDPOINT = f"{BASE_URL}/tokenize"


def get_vram_usage():
    try:
        output = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,nounits,noheader"],
            encoding="utf-8",
        )
        return sum(int(x.strip()) for x in output.strip().split("\n"))
    except Exception:
        return 0


def get_ram_usage():
    try:
        with open("/proc/meminfo", "r") as f:
            meminfo = {}
            for line in f:
                parts = line.split()
                if len(parts) >= 2:
                    meminfo[parts[0]] = int(parts[1])
            total = meminfo.get("MemTotal:", 0)
            available = meminfo.get("MemAvailable:", 0)
            return (total - available) / 1024  # MB
    except Exception:
        return 0


def count_tokens(text: str) -> int:
    """Exact token count via llama-server /tokenize (falls back to char heuristic)."""
    try:
        resp = requests.post(
            TOKENIZE_ENDPOINT,
            json={
                "content": text,
                "model": FLASH_MODEL,
                "add_special": False,
                "parse_special": False,
            },
            timeout=120,
        )
        resp.raise_for_status()
        tokens = resp.json().get("tokens")
        if isinstance(tokens, list):
            return len(tokens)
    except Exception as e:
        print(f"tokenize fallback ({e})", flush=True)
    return max(1, len(text) // 4)


def generate_dummy_prompt(token_count: int) -> str:
    """Build a prompt whose tokenized length is ~token_count (O(1) tokenize calls)."""
    unit = "The quick brown fox jumps over the lazy dog. "
    unit_tok = max(1, count_tokens(unit))
    reps = max(1, token_count // unit_tok)
    text = unit * reps
    n = count_tokens(text)
    if n < token_count:
        extra = (token_count - n + unit_tok - 1) // unit_tok
        text += unit * extra
        n = count_tokens(text)
    if n > token_count:
        overflow_units = (n - token_count + unit_tok - 1) // unit_tok
        if overflow_units > 0 and reps > overflow_units:
            text = unit * (reps - overflow_units + (0 if n - overflow_units * unit_tok <= token_count else 0))
            # Recompute cleanly from target
            text = unit * max(1, token_count // unit_tok)
            n = count_tokens(text)
            while n < token_count:
                text += unit
                n = count_tokens(text)
            while n > token_count and len(text) >= len(unit):
                text = text[: -len(unit)]
                n = count_tokens(text)
    # Pad with short tokens if still short
    while count_tokens(text) < token_count:
        text += " x"
    return text


# Sizes at/above this are NVMe-bound (mmap expert paging) — secondary signal only.
NVME_BOUND_SIZE = 32000
# Cap decode observation for long-context rows so wall time isn't dominated by
# sub-1 t/s NVMe paging on a full 100-token completion.
DECODE_MEASURE_CAP_SEC = 60


def _warm_up_completion():
    """Short completion so cold-load doesn't dominate the first size point."""
    print("Warm-up completion (small prompt, same model)...", flush=True)
    erase_slots(FLASH_MODEL, label="before warm-up")
    payload = {
        "model": FLASH_MODEL,
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Reply with exactly: ok"},
        ],
        "max_tokens": 8,
        "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
        **repro_params(),
    }
    try:
        resp = requests.post(ENDPOINT, json=payload, timeout=600)
        resp.raise_for_status()
        print("Warm-up done.", flush=True)
    except requests.exceptions.RequestException as e:
        print(f"Warm-up failed (continuing): {e}", flush=True)


def run_hardware_limits_benchmark():
    context_sizes = [2000, 8000, 32000, 64000]
    results = {}

    print("Starting Hardware Limits Benchmark...", flush=True)
    _warm_up_completion()

    for size in context_sizes:
        nvme_bound = size >= NVME_BOUND_SIZE
        primary = not nvme_bound
        print(
            f"Testing context size: {size} tokens "
            f"(primary={primary}, nvme_bound={nvme_bound})",
            flush=True,
        )
        prompt = generate_dummy_prompt(size)
        user_content = f"Summarize this text: {prompt}\n\nSummary:"
        actual_tokens = count_tokens(user_content)
        print(f"  calibrated user-payload tokens={actual_tokens}", flush=True)

        payload = {
            "model": FLASH_MODEL,
            "messages": [
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": user_content},
            ],
            "max_tokens": 100,
            "stream": True,
            "stream_options": {"include_usage": True},
            # Hardware matrix measures prefill/decode — not CoT quality.
            # Module 2/3 keep thinking enabled.
            "chat_template_kwargs": {"enable_thinking": False},
            # Independent per-size measurement (no cross-size prefix credit);
            # temperature 0 + fixed seed + cache_prompt off come from repro_params().
            **repro_params(),
        }
        erase_slots(FLASH_MODEL, label=f"before {size}")

        start_time = time.time()
        ttft = None
        tokens_generated = 0
        prompt_tokens_reported = None
        peak_ram = get_ram_usage()
        peak_vram = get_vram_usage()
        last_sample = start_time
        decode_capped = False

        try:
            response = requests.post(
                ENDPOINT, json=payload, stream=True, timeout=28800
            )
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
                            delta = (
                                (chunk.get("choices") or [{}])[0]
                                .get("delta", {})
                                .get("content")
                            )
                            if delta:
                                tokens_generated += max(1, len(delta.split()))
                            usage = chunk.get("usage") or {}
                            if usage.get("completion_tokens"):
                                tokens_generated = int(usage["completion_tokens"])
                            if usage.get("prompt_tokens"):
                                prompt_tokens_reported = int(usage["prompt_tokens"])
                        except json.JSONDecodeError:
                            tokens_generated += 1

                now = time.time()
                if now - last_sample >= 1.0:
                    peak_ram = max(peak_ram, get_ram_usage())
                    peak_vram = max(peak_vram, get_vram_usage())
                    last_sample = now

                # Long-context decode is NVMe-bound; cap observation window.
                if (
                    nvme_bound
                    and ttft is not None
                    and (now - start_time - ttft) >= DECODE_MEASURE_CAP_SEC
                ):
                    decode_capped = True
                    print(
                        f"  decode window capped at {DECODE_MEASURE_CAP_SEC}s "
                        f"(NVMe-bound; not a primary regression signal)",
                        flush=True,
                    )
                    response.close()
                    break

            peak_ram = max(peak_ram, get_ram_usage())
            peak_vram = max(peak_vram, get_vram_usage())

            total_time = time.time() - start_time
            decode_time = total_time - ttft if ttft else 0
            decode_throughput = (
                tokens_generated / decode_time if decode_time > 0 else 0
            )
            prefill_throughput = size / ttft if ttft and ttft > 0 else 0

            results[size] = {
                "wall_sec": round(total_time, 3),
                "ttft_sec": round(ttft, 3) if ttft else None,
                "prefill_throughput_tps": round(prefill_throughput, 2),
                "decode_throughput_tps": round(decode_throughput, 2),
                "peak_ram_mb": round(peak_ram, 2),
                "peak_vram_mb": peak_vram,
                "completion_tokens": tokens_generated,
                "prompt_tokens_reported": prompt_tokens_reported,
                "prompt_tokens_target": size,
                "prompt_tokens_actual": actual_tokens,
                "primary": primary,
                "nvme_bound": nvme_bound,
            }
            if nvme_bound:
                results[size]["decode_note"] = (
                    "NVMe-bound mmap expert paging; not a primary regression signal. "
                    "Primary metrics are 2k/8k."
                )
                results[size]["decode_measure_cap_sec"] = DECODE_MEASURE_CAP_SEC
                results[size]["decode_window_capped"] = decode_capped
            print(f"Results for {size}: {results[size]}", flush=True)

        except requests.exceptions.RequestException as e:
            print(f"Failed for size {size}: {e}", flush=True)
            results[size] = {
                "error": str(e),
                "peak_ram_mb": round(peak_ram, 2),
                "peak_vram_mb": peak_vram,
                "primary": primary,
                "nvme_bound": nvme_bound,
            }

    return results


if __name__ == "__main__":
    results = run_hardware_limits_benchmark()
    with open("telemetry_results.json", "w") as f:
        json.dump(results, f, indent=2)
    print("Saved telemetry results to telemetry_results.json", flush=True)
