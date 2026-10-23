"""Shared substrate telemetry and inference helpers for Project Alpha 4-Stone profilers.

Self-contained module replacing archived tests.benchmark_suite dependencies.
"""
import os
import subprocess
import time
from typing import Dict, Any

try:
    import requests
except ImportError:
    requests = None

# Base URL resolution: checks OPENAI_BASE_URL, LLAMA_SERVER_URL, or defaults to Watchtower / local
RAW_BASE = os.getenv("OPENAI_BASE_URL") or os.getenv("LLAMA_SERVER_URL") or "http://127.0.0.1:8080"
if RAW_BASE.endswith("/v1"):
    BASE_URL = RAW_BASE[:-3].rstrip("/")
else:
    BASE_URL = RAW_BASE.rstrip("/")

CHAT_ENDPOINT = f"{BASE_URL}/v1/chat/completions"
TOKENIZE_ENDPOINT = f"{BASE_URL}/tokenize"

DEFAULT_MODEL = os.getenv("BENCHMARK_MODEL") or os.getenv("BENCH_MODEL") or "qwen36-coder-hybrid"
SEED = 12345


def repro_params(**overrides) -> Dict[str, Any]:
    """Sampling knobs for reproducible runs (greedy, fixed seed, no prompt cache)."""
    params = {"temperature": 0, "seed": SEED, "cache_prompt": False}
    params.update(overrides)
    return params


def erase_slots(model: str = DEFAULT_MODEL, label: str = "") -> Dict[str, Any]:
    """Erase every KV slot on the server. Never raises; never triggers a router model load."""
    if requests is None:
        return {"model": model, "erased": [], "errors": ["requests library missing"]}

    summary = {"model": model, "erased": [], "errors": []}
    query = {"model": model, "autoload": "false"}
    try:
        resp = requests.get(f"{BASE_URL}/slots", params=query, timeout=10)
        if resp.status_code != 200:
            summary["errors"].append(f"GET /slots -> {resp.status_code}: {resp.text[:120]}")
            return summary

        slots = resp.json()
        if not isinstance(slots, list):
            summary["errors"].append(f"GET /slots -> non-list payload: {type(slots).__name__}")
            return summary

        for s in slots:
            slot_id = s.get("id")
            if slot_id is None:
                continue
            post_resp = requests.post(
                f"{BASE_URL}/slots/{slot_id}?action=erase",
                timeout=10,
            )
            if post_resp.status_code == 200:
                summary["erased"].append(slot_id)
            else:
                summary["errors"].append(
                    f"POST /slots/{slot_id}?action=erase -> {post_resp.status_code}: {post_resp.text[:120]}"
                )
    except Exception as e:
        summary["errors"].append(f"erase_slots exception: {e}")

    return summary


def get_vram_usage() -> int:
    """Returns used VRAM across local GPUs in MiB via nvidia-smi."""
    try:
        output = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,nounits,noheader"],
            encoding="utf-8",
        )
        return sum(int(x.strip()) for x in output.strip().split("\n") if x.strip())
    except Exception:
        return 0


def get_ram_usage() -> float:
    """Returns host RAM used in MiB via /proc/meminfo."""
    try:
        with open("/proc/meminfo", "r") as f:
            meminfo = {}
            for line in f:
                parts = line.split()
                if len(parts) >= 2:
                    meminfo[parts[0]] = int(parts[1])
            total = meminfo.get("MemTotal:", 0)
            available = meminfo.get("MemAvailable:", 0)
            return (total - available) / 1024  # MiB
    except Exception:
        return 0.0


def count_tokens(text: str, model: str = DEFAULT_MODEL) -> int:
    """Exact token count via llama-server /tokenize with heuristic fallback."""
    if requests is not None:
        try:
            resp = requests.post(
                TOKENIZE_ENDPOINT,
                json={
                    "content": text,
                    "model": model,
                    "add_special": False,
                    "parse_special": False,
                },
                timeout=30,
            )
            if resp.status_code == 200:
                tokens = resp.json().get("tokens")
                if isinstance(tokens, list):
                    return len(tokens)
        except Exception:
            pass
    return max(1, len(text) // 4)


def generate_dummy_prompt(token_count: int, model: str = DEFAULT_MODEL) -> str:
    """Build a prompt whose tokenized length is ~token_count."""
    unit = "The quick brown fox jumps over the lazy dog. "
    unit_tok = max(1, count_tokens(unit, model=model))
    reps = max(1, token_count // unit_tok)
    text = unit * reps
    n = count_tokens(text, model=model)
    if n < token_count:
        extra = (token_count - n + unit_tok - 1) // unit_tok
        text += unit * extra
        n = count_tokens(text, model=model)
    if n > token_count:
        overflow_units = (n - token_count + unit_tok - 1) // unit_tok
        if overflow_units > 0 and reps > overflow_units:
            text = unit * (reps - overflow_units)
            n = count_tokens(text, model=model)
            while n < token_count:
                text += unit
                n = count_tokens(text, model=model)
            while n > token_count and len(text) >= len(unit):
                text = text[:-len(unit)]
                n = count_tokens(text, model=model)
    while count_tokens(text, model=model) < token_count:
        text += " x"
    return text
