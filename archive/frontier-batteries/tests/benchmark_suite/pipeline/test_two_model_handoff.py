"""Module 3: 180B planner -> 35B worker handoff.

Improvements vs. first DEGRADED run:
- Prefer message.content; fall back to reasoning_content if the plan is thinking-only.
- Retry planner once when the extracted Phase 1.1 block is empty.
- Do not mark worker success on empty prompts; record failure_reason.
- Persist planner/worker previews for frontier_full_eval.json.

Harness v3: temperature 0 / fixed seed / cache_prompt off, slot erase before each pass,
and wall-clock + token usage per request in the result dict.
Planner capped at PLANNER_MAX_TOKENS with a Phase-1.1-only brief prompt.
"""
import os
import sys
import time
import requests

try:
    from tests.benchmark_suite.common import (
        CHAT_ENDPOINT as ENDPOINT,
        FLASH_MODEL,
        WORKER_MODEL,
        erase_slots,
        repro_params,
        sum_metrics,
        timed_post,
        usage_metrics,
    )
except ImportError:  # executed directly as a script
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
    from tests.benchmark_suite.common import (
        CHAT_ENDPOINT as ENDPOINT,
        FLASH_MODEL,
        WORKER_MODEL,
        erase_slots,
        repro_params,
        sum_metrics,
        timed_post,
        usage_metrics,
    )

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
SPECS_DIR = os.path.join(PROJECT_ROOT, "specs")
RESPONSE_LOG_CHARS = 8000


def message_text(message: dict) -> str:
    if not isinstance(message, dict):
        return ""
    content = (message.get("content") or "").strip()
    reasoning = (message.get("reasoning_content") or "").strip()
    if content:
        return content
    return reasoning


def truncate(text: str, limit: int = RESPONSE_LOG_CHARS) -> str:
    text = text or ""
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n...[truncated {len(text) - limit} chars]"


def extract_phase_1_1(plan_content: str) -> str:
    phase_1_1 = ""
    in_phase = False
    for line in (plan_content or "").split("\n"):
        if "Phase 1.1" in line:
            in_phase = True
        elif in_phase and line.startswith("#"):
            break
        if in_phase:
            phase_1_1 += line + "\n"
    return phase_1_1.strip()


# Cap Flash planner completion so CoT+answer stay brief (Phase 1.1 bullets only).
PLANNER_MAX_TOKENS = 700


def request_planner(prompt: str) -> tuple[str, dict]:
    body, metrics = timed_post(
        {
            "model": FLASH_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": PLANNER_MAX_TOKENS,
            "chat_template_kwargs": {"enable_thinking": True},
            **repro_params(),
        }
    )
    return message_text(body["choices"][0]["message"]), metrics


def run_pipeline_benchmark():
    results = {
        "swap_latency_sec": None,
        "worker_time_sec": None,
        "worker_success": False,
        "failure_reason": None,
        "planner_chars": 0,
        "phase_1_1_chars": 0,
        "planner_preview": "",
        "worker_preview": "",
        "planner_metrics": None,
        "worker_metrics": None,
    }
    planner_runs = []
    print("Running Pipeline Benchmark: Pass A (Planner)", flush=True)
    erase_slots(FLASH_MODEL, label="before planner")

    os.makedirs(SPECS_DIR, exist_ok=True)
    spec_path = os.path.join(SPECS_DIR, "BENCHMARK_ARCH_PLAN.md")

    planner_prompt = f"""
Output ONLY:
### Phase 1.1: Redis Connection Pool
Then 3–6 numbered bullets for a Redis connection pool (max 100 connections).

Rules: Phase 1.1 only. Numbered bullets only. No prose essay. No code.
Put the answer in content (not only private reasoning). Budget: ≤{PLANNER_MAX_TOKENS} tokens.
"""

    plan_content = ""
    try:
        plan_content, m = request_planner(planner_prompt)
        planner_runs.append(m)
        phase_1_1 = extract_phase_1_1(plan_content)
        if not phase_1_1:
            print("Planner returned no Phase 1.1 — retrying once...", flush=True)
            retry_prompt = (
                planner_prompt
                + "\n\nIMPORTANT: Brief reply only. "
                f"max_tokens={PLANNER_MAX_TOKENS}. "
                "Include '### Phase 1.1: Redis Connection Pool' with at least "
                "three numbered implementation bullets. No prose, no code."
            )
            erase_slots(FLASH_MODEL, label="before planner retry")
            plan_content, m = request_planner(retry_prompt)
            planner_runs.append(m)
            phase_1_1 = extract_phase_1_1(plan_content)
    except Exception as e:
        print(f"Planner failed: {e}", flush=True)
        results["failure_reason"] = f"planner_error: {e}"
        plan_content = ""
        phase_1_1 = ""

    with open(spec_path, "w") as f:
        f.write(plan_content or "")

    results["planner_metrics"] = sum_metrics(planner_runs)
    results["planner_runs"] = planner_runs
    results["planner_max_tokens"] = PLANNER_MAX_TOKENS
    results["planner_chars"] = len(plan_content or "")
    results["phase_1_1_chars"] = len(phase_1_1 or "")
    results["planner_preview"] = truncate(plan_content or "")
    print(
        f"Saved plan to {spec_path} "
        f"(chars={results['planner_chars']}, phase_1_1={results['phase_1_1_chars']})",
        flush=True,
    )

    if not phase_1_1:
        results["failure_reason"] = results["failure_reason"] or "empty_phase_1_1_after_retry"
        print("Pipeline Result: aborted — empty Phase 1.1 after retry", flush=True)
        results["swap_latency_sec"] = 0.0
        results["worker_time_sec"] = 0.0
        results["worker_success"] = False
        return results

    print("Triggering Model Swap to Tier 1 Driver (Qwen 3.6 35B)", flush=True)
    swap_start = time.time()
    try:
        requests.post(
            ENDPOINT,
            json={
                "model": WORKER_MODEL,
                "messages": [{"role": "user", "content": "ping"}],
                "max_tokens": 1,
                **repro_params(),
            },
            timeout=600,
        )
        results["swap_latency_sec"] = round(time.time() - swap_start, 3)
    except Exception as e:
        print(f"Model swap warm failed: {e}", flush=True)
        results["swap_latency_sec"] = round(time.time() - swap_start, 3)
        results["failure_reason"] = f"swap_failed: {e}"
        results["worker_time_sec"] = 0.0
        results["worker_success"] = False
        return results

    print("Running Pipeline Benchmark: Pass B (Worker)", flush=True)
    worker_prompt = (
        "Execute Phase 1.1 strictly without hallucinating unrequested architecture:\n"
        f"{phase_1_1}"
    )

    erase_slots(WORKER_MODEL, label="before worker")
    start_time = time.time()
    try:
        response = requests.post(
            ENDPOINT,
            json={
                "model": WORKER_MODEL,
                "messages": [{"role": "user", "content": worker_prompt}],
                "max_tokens": 500,
                **repro_params(),
            },
            timeout=60,
        )
        response.raise_for_status()
        worker_body = response.json()
        worker_content = message_text(worker_body["choices"][0]["message"])
        worker_time = time.time() - start_time
        results["worker_metrics"] = usage_metrics(worker_body, worker_time)
        results["worker_time_sec"] = round(worker_time, 3)
        results["worker_preview"] = truncate(worker_content)
        results["worker_success"] = worker_time < 15.0 and len(worker_content) > 10
        if not results["worker_success"]:
            if worker_time >= 15.0:
                results["failure_reason"] = f"worker_too_slow: {worker_time:.3f}s"
            else:
                results["failure_reason"] = f"worker_content_too_short: {len(worker_content)} chars"
    except requests.exceptions.Timeout:
        results["worker_time_sec"] = round(time.time() - start_time, 3)
        results["worker_preview"] = "TIMEOUT"
        results["worker_success"] = False
        results["failure_reason"] = "worker_timeout"
    except Exception as e:
        results["worker_time_sec"] = round(time.time() - start_time, 3)
        results["worker_preview"] = f"ERROR: {e}"
        results["worker_success"] = False
        results["failure_reason"] = f"worker_error: {e}"

    print(
        f"Pipeline Result: Swap {results['swap_latency_sec']}s, "
        f"Worker {results['worker_time_sec']}s, Success: {results['worker_success']}"
        + (f" ({results['failure_reason']})" if results["failure_reason"] else ""),
        flush=True,
    )
    return results


if __name__ == "__main__":
    import json

    res = run_pipeline_benchmark()
    with open("pipeline_results.json", "w") as f:
        json.dump(res, f, indent=2)
    print("Saved pipeline results to pipeline_results.json", flush=True)
