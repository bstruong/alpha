"""Shared helpers for the frontier benchmark modules (1-3).

- One canonical Flash API model id (matches `alias` in engine/models.ini).
- Reproducible sampling knobs (temperature 0, fixed seed, no prompt cache).
- llama-server slot erase between modules / traps (needs `slot-save-path` in the preset).
- Per-request metrics (wall clock + usage + llama.cpp timings) for the JSON report.
"""
import time

import requests

BASE_URL = "http://localhost:8080"
CHAT_ENDPOINT = f"{BASE_URL}/v1/chat/completions"

# Canonical id = router section name = what `GET /v1/models` returns ("qwen3.8-flash").
# The models.ini alias `qwen-3.8-flash` is still accepted by the router but not used by clients.
FLASH_MODEL = "qwen3.8-flash"
WORKER_MODEL = "qwen36-coder"

SEED = 12345


def repro_params(**overrides) -> dict:
    """Sampling knobs for reproducible runs (greedy, fixed seed, no prompt cache)."""
    params = {"temperature": 0, "seed": SEED, "cache_prompt": False}
    params.update(overrides)
    return params


def erase_slots(model: str = FLASH_MODEL, label: str = "") -> dict:
    """Erase every KV slot on the server. Never raises; never triggers a router model load."""
    summary = {"model": model, "erased": [], "errors": []}
    query = {"model": model, "autoload": "false"}
    try:
        resp = requests.get(f"{BASE_URL}/slots", params=query, timeout=30)
        if resp.status_code != 200:
            summary["errors"].append(f"GET /slots -> {resp.status_code}: {resp.text[:120]}")
            _log_erase(summary, label)
            return summary
        slots = resp.json()
        ids = [s.get("id") for s in slots if isinstance(s, dict) and s.get("id") is not None]
    except Exception as e:
        summary["errors"].append(f"GET /slots: {e}")
        _log_erase(summary, label)
        return summary

    for slot_id in ids:
        try:
            # Router proxies POSTs by the JSON "model" field; single mode ignores it.
            resp = requests.post(
                f"{BASE_URL}/slots/{slot_id}",
                params={"action": "erase", "autoload": "false"},
                json={"model": model},
                timeout=60,
            )
            if resp.status_code == 200:
                summary["erased"].append(slot_id)
            else:
                summary["errors"].append(f"slot {slot_id} -> {resp.status_code}: {resp.text[:120]}")
        except Exception as e:
            summary["errors"].append(f"slot {slot_id}: {e}")
    _log_erase(summary, label)
    return summary


def _log_erase(summary: dict, label: str) -> None:
    suffix = f" [{label}]" if label else ""
    if summary["errors"]:
        print(f"  slot erase{suffix}: erased={summary['erased']} errors={summary['errors']}", flush=True)
    else:
        print(f"  slot erase{suffix}: erased={summary['erased']}", flush=True)


def usage_metrics(body: dict, wall_sec: float) -> dict:
    """Extract wall-clock + token usage (+ llama.cpp timings) from a completion response."""
    body = body if isinstance(body, dict) else {}
    usage = body.get("usage") or {}
    details = usage.get("completion_tokens_details") or {}
    timings = body.get("timings") or {}
    metrics = {
        "wall_sec": round(wall_sec, 3),
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": usage.get("completion_tokens"),
        "reasoning_tokens": details.get("reasoning_tokens", usage.get("reasoning_tokens")),
    }
    if timings:
        metrics["prompt_per_second"] = timings.get("prompt_per_second")
        metrics["predicted_per_second"] = timings.get("predicted_per_second")
    return metrics


def timed_post(payload: dict, timeout: int = 1800) -> tuple[dict, dict]:
    """POST a chat completion; returns (response_json, metrics)."""
    start = time.time()
    response = requests.post(CHAT_ENDPOINT, json=payload, timeout=timeout)
    wall = time.time() - start
    response.raise_for_status()
    body = response.json()
    return body, usage_metrics(body, wall)


def sum_metrics(items: list[dict]) -> dict:
    """Aggregate token/wall metrics across several requests."""
    total = {"wall_sec": 0.0, "prompt_tokens": 0, "completion_tokens": 0, "reasoning_tokens": 0, "requests": 0}
    for m in items:
        if not m:
            continue
        total["requests"] += 1
        total["wall_sec"] += m.get("wall_sec") or 0.0
        for key in ("prompt_tokens", "completion_tokens", "reasoning_tokens"):
            total[key] += m.get(key) or 0
    total["wall_sec"] = round(total["wall_sec"], 3)
    return total
