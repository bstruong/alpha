#!/usr/bin/env python3
"""Berserker Validation & Benchmark Suite — Base Runner.

Phase 1: CLI scaffolding with timestamped output directories.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

RESULTS_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")
_base_url = (os.getenv("ALPHA_SERVER_URL") or os.getenv("OPENAI_BASE_URL") or "http://192.168.1.92:8080/v1").rstrip("/")
SERVER_URL = _base_url if _base_url.endswith("/chat/completions") else f"{_base_url}/chat/completions"



# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def setup_timestamp_dir() -> str:
    """Create a timestamped results directory and return its path."""
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = os.path.join(RESULTS_ROOT, ts)
    os.makedirs(path, exist_ok=True)
    return path


def save_metrics(results_dir: str, data: dict) -> str:
    """Write *data* to *results_dir*/metrics.json and return the path."""
    metrics_path = os.path.join(results_dir, "metrics.json")
    with open(metrics_path, "w") as fh:
        json.dump(data, fh, indent=2)
    return metrics_path


def send_completion(prompt: str, system: str = "") -> dict:
    """Send a synthetic payload to the local server and return parsed JSON."""
    import urllib.request

    payload = {
        "model": "default",
        "messages": [
            {"role": "system", "content": system} if system else {"role": "user", "content": "Say hello"},
            {"role": "user", "content": prompt},
        ],
        "max_tokens": 128,
        "temperature": 0.0,
    }
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        SERVER_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


# ---------------------------------------------------------------------------
# Subcommand: perf
# ---------------------------------------------------------------------------

def cmd_perf(args) -> int:
    """Performance benchmark subcommand.

    Measures cold/warm/append TTFT and token throughput.
    """
    results_dir = setup_timestamp_dir()

    if args.dry_run:
        print("[dry-run] perf: skipping actual server calls")
        metrics = {"status": "dry_run", "subcommand": "perf"}
        path = save_metrics(results_dir, metrics)
        print(f"Metrics saved to {path}")
        return 0

    try:
        # --- Cold TTFT ---
        cold_start = time.perf_counter()
        resp = send_completion("Tell me about the capital of France.")
        cold_ttft = time.perf_counter() - cold_start
        cold_usage = resp.get("usage", {})

        # --- Warm TTFT (identical prompt) ---
        warm_start = time.perf_counter()
        resp = send_completion("Tell me about the capital of France.")
        warm_ttft = time.perf_counter() - warm_start
        warm_usage = resp.get("usage", {})

        # --- Append TTFT (original + suffix) ---
        append_start = time.perf_counter()
        resp = send_completion(
            "Tell me about the capital of France. Now add information about its population."
        )
        append_ttft = time.perf_counter() - append_start
        append_usage = resp.get("usage", {})

        metrics = {
            "subcommand": "perf",
            "cold_ttft_s": round(cold_ttft, 4),
            "warm_ttft_s": round(warm_ttft, 4),
            "append_ttft_s": round(append_ttft, 4),
            "cold_usage": cold_usage,
            "warm_usage": warm_usage,
            "append_usage": append_usage,
        }
        # Compute tokens/sec from usage stats
        for label, usage in [("cold", cold_usage), ("warm", warm_usage), ("append", append_usage)]:
            ttft_key = f"{label}_ttft_s"
            total_tokens = usage.get("total_tokens", 0)
            if total_tokens > 0:
                metrics[f"{label}_toks_per_s"] = round(total_tokens / metrics[ttft_key], 2)

        path = save_metrics(results_dir, metrics)
        print(json.dumps(metrics, indent=2))
        print(f"Metrics saved to {path}")
        return 0

    except Exception as exc:
        print(f"[perf] error: {exc}", file=sys.stderr)
        metrics = {"subcommand": "perf", "error": str(exc)}
        path = save_metrics(results_dir, metrics)
        return 1


# ---------------------------------------------------------------------------
# Subcommand: soak
# ---------------------------------------------------------------------------

def cmd_soak(args) -> int:
    """Memory-soak subcommand.

    Samples VRAM and system memory over *--duration* seconds.
    Fails if VRAM drift > 256 MB or Swap growth > 256 MB.
    """
    results_dir = setup_timestamp_dir()
    duration = args.duration
    interval = 5  # seconds between samples

    def get_vram_mb():
        try:
            out = subprocess.check_output(
                ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                stderr=subprocess.DEVNULL,
                timeout=10,
            ).decode().strip()
            return float(out)
        except Exception:
            return None

    def get_meminfo():
        try:
            mem = {}
            with open("/proc/meminfo") as fh:
                for line in fh:
                    parts = line.split()
                    if len(parts) >= 2:
                        key = parts[0].rstrip(":")
                        mem[key] = int(parts[1])  # kB
            return mem
        except Exception:
            return {}

    def get_swap_mb(meminfo):
        return round(meminfo.get("SwapFree", 0) / 1024, 1)

    samples = []
    vram_start = get_vram_mb()
    meminfo_start = get_meminfo()
    swap_start_mb = get_swap_mb(meminfo_start)

    print(f"[soak] running for {duration}s (interval={interval}s)")
    end_time = time.monotonic() + duration

    while time.monotonic() < end_time:
        vram = get_vram_mb()
        meminfo = get_meminfo()
        swap_mb = get_swap_mb(meminfo)
        samples.append({
            "vram_used_mb": vram,
            "mem_available_kb": meminfo.get("MemAvailable"),
            "swap_free_mb": swap_mb,
        })
        print(f"  vram={vram}MB  mem_avail={meminfo.get('MemAvailable')}kB  swap={swap_mb}MB")
        time.sleep(interval)

    # --- Evaluate drift ---
    if vram_start is not None and vram is not None:
        vram_drift = abs(vram - vram_start)
        vram_ok = vram_drift <= 256
    else:
        vram_drift = None
        vram_ok = True

    swap_drift = abs(swap_mb - swap_start_mb) if swap_start_mb is not None else None
    swap_ok = swap_drift is None or swap_drift <= 256

    metrics = {
        "subcommand": "soak",
        "duration_s": duration,
        "samples": samples,
        "vram_drift_mb": round(vram_drift, 1) if vram_drift is not None else None,
        "vram_ok": vram_ok,
        "swap_drift_mb": round(swap_drift, 1) if swap_drift is not None else None,
        "swap_ok": swap_ok,
        "passed": vram_ok and swap_ok,
    }
    path = save_metrics(results_dir, metrics)
    print(json.dumps(metrics, indent=2))
    print(f"Metrics saved to {path}")
    return 0 if metrics["passed"] else 1


# ---------------------------------------------------------------------------
# Subcommand: quality
# ---------------------------------------------------------------------------

def cmd_quality(args) -> int:
    """Code-quality harness subcommand.

    Iterates over validation/tasks/<name>/ directories, runs their test
    commands, and records pass/fail rates.
    """
    results_dir = setup_timestamp_dir()
    tasks_root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tasks")

    if args.dry_run:
        print("[dry-run] quality: listing expected task directories")
        if os.path.isdir(tasks_root):
            for entry in sorted(os.listdir(tasks_root)):
                print(f"  {entry}/")
        else:
            print(f"  (no tasks directory at {tasks_root})")
        metrics = {"status": "dry_run", "subcommand": "quality"}
        path = save_metrics(results_dir, metrics)
        print(f"Metrics saved to {path}")
        return 0

    results = []
    total = 0
    passed = 0

    if not os.path.isdir(tasks_root):
        print(f"[quality] no tasks directory at {tasks_root}", file=sys.stderr)
        metrics = {"subcommand": "quality", "error": "no tasks directory", "results": []}
        path = save_metrics(results_dir, metrics)
        return 1

    for task_name in sorted(os.listdir(tasks_root)):
        task_dir = os.path.join(tasks_root, task_name)
        if not os.path.isdir(task_dir):
            continue

        # Each task may contain a `test.sh` or `run.sh` with the command to execute.
        # Also support a `cmd` text file for simple commands.
        test_script = os.path.join(task_dir, "test.sh")
        run_script = os.path.join(task_dir, "run.sh")
        cmd_file = os.path.join(task_dir, "cmd")

        if os.path.isfile(test_script):
            cmd = ["bash", test_script]
        elif os.path.isfile(run_script):
            cmd = ["bash", run_script]
        elif os.path.isfile(cmd_file):
            with open(cmd_file) as fh:
                cmd = fh.read().strip().split()
        else:
            print(f"[quality] skipping {task_name} (no test/run/cmd file)")
            continue

        total += 1
        print(f"[quality] running {task_name}: {' '.join(cmd)}")
        try:
            proc = subprocess.run(cmd, cwd=task_dir, capture_output=True, text=True, timeout=60)
            ok = proc.returncode == 0
            if ok:
                passed += 1
            results.append({
                "task": task_name,
                "passed": ok,
                "returncode": proc.returncode,
                "stdout": proc.stdout[-500:] if proc.stdout else "",
                "stderr": proc.stderr[-500:] if proc.stderr else "",
            })
            status = "PASS" if ok else "FAIL"
            print(f"  [{status}] {task_name}")
        except subprocess.TimeoutExpired:
            results.append({"task": task_name, "passed": False, "returncode": -1, "error": "timeout"})
            print(f"  [FAIL] {task_name} (timeout)")

    metrics = {
        "subcommand": "quality",
        "total": total,
        "passed": passed,
        "failed": total - passed,
        "pass_rate": round(passed / total, 4) if total else 0,
        "results": results,
    }
    path = save_metrics(results_dir, metrics)
    print(json.dumps(metrics, indent=2))
    print(f"Metrics saved to {path}")
    return 0 if metrics["failed"] == 0 else 1


# ---------------------------------------------------------------------------
# Subcommand: all
# ---------------------------------------------------------------------------

def cmd_all(args) -> int:
    """Run every subcommand in sequence."""
    runners = {
        "perf": cmd_perf,
        "quality": cmd_quality,
        "soak": cmd_soak,
    }
    overall = 0
    for name, runner in runners.items():
        print(f"\n{'='*60}")
        print(f"  Running: {name}")
        print(f"{'='*60}")
        # Rebuild args namespace for each subcommand
        sub_args = argparse.Namespace(**{k: v for k, v in vars(args).items() if k != "func"})
        if not hasattr(sub_args, "dry_run"):
            sub_args.dry_run = False
        if not hasattr(sub_args, "duration"):
            sub_args.duration = 30
        rc = runner(sub_args)
        overall |= rc
    return overall


# ---------------------------------------------------------------------------
# CLI Parser
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="run_suite",
        description="Berserker Validation & Benchmark Suite",
    )
    sub = parser.add_subparsers(dest="command", help="Available subcommands")

    # -- perf --
    perf_p = sub.add_parser("perf", help="Performance benchmark (TTFT, throughput)")
    perf_p.add_argument("--dry-run", action="store_true", help="Skip actual server calls")
    perf_p.set_defaults(func=cmd_perf)

    # -- soak --
    soak_p = sub.add_parser("soak", help="Memory-soak stability monitor")
    soak_p.add_argument("--duration", type=int, default=30, help="Run duration in seconds (default: 30)")
    soak_p.set_defaults(func=cmd_soak)

    # -- quality --
    qual_p = sub.add_parser("quality", help="Polyglot code-quality harness")
    qual_p.add_argument("--dry-run", action="store_true", help="List task dirs without running")
    qual_p.set_defaults(func=cmd_quality)

    # -- all --
    all_p = sub.add_parser("all", help="Run all subcommands in sequence")
    all_p.set_defaults(func=cmd_all)

    return parser


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------

def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        return 0

    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
