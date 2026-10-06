#!/usr/bin/env python3
"""Unified CLI runner for the validation_v2 suite.

Subcommands: perf, soak, quality, all.

Metrics are saved to validation_v2/results/<timestamp>/metrics.json.
"""

from __future__ import annotations

import argparse
import datetime
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from perf import measure_streaming_ttft
from soak import calculate_drift

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent
TASKS_DIR = BASE_DIR / "tasks"
RESULTS_DIR = BASE_DIR / "results"

TASK_SCRIPTS: dict[str, tuple[Path, str]] = {
    "go-merge-intervals": (TASKS_DIR / "go-merge-intervals" / "test.sh", "go"),
    "ts-semver-compare": (TASKS_DIR / "ts-semver-compare" / "test.sh", "node"),
    "python-token-bucket": (TASKS_DIR / "python-token-bucket" / "test.sh", "python3"),
    "java-lru-cache": (TASKS_DIR / "java-lru-cache" / "test.sh", "java"),
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ensure_results_dir() -> Path:
    """Create a timestamped results directory and return its path."""
    timestamp = datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y%m%dT%H%M%S")
    result_path = RESULTS_DIR / timestamp
    result_path.mkdir(parents=True, exist_ok=True)
    return result_path


def _save_metrics(metrics: dict[str, Any], results_dir: Path) -> None:
    """Write *metrics* to results_dir/metrics.json."""
    metrics_path = results_dir / "metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2, default=str))


def _run_task(name: str, dry_run: bool = False) -> dict[str, Any]:
    """Execute a single polyglot task and return its result dict."""
    script_path, _ = TASK_SCRIPTS[name]
    result: dict[str, Any] = {
        "task": name,
        "status": "pending",
        "duration_s": 0.0,
    }

    if dry_run:
        result["status"] = "dry_run"
        return result

    start = time.perf_counter()
    try:
        proc = subprocess.run(
            ["bash", str(script_path)],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        elapsed = time.perf_counter() - start
        result["duration_s"] = elapsed
        if proc.returncode == 0:
            result["status"] = "passed"
            result["stdout"] = proc.stdout.strip()
        else:
            result["status"] = "failed"
            result["stderr"] = proc.stderr.strip()
    except subprocess.TimeoutExpired:
        result["status"] = "timeout"
    except FileNotFoundError:
        result["status"] = "skipped"
        result["error"] = f"bash not found or script missing: {script_path}"

    return result


# ---------------------------------------------------------------------------
# Subcommand handlers
# ---------------------------------------------------------------------------

def run_perf(args: argparse.Namespace) -> dict[str, Any]:
    """Run the streaming TTFT performance test."""
    results_dir = _ensure_results_dir()
    metrics: dict[str, Any] = {"phase": "perf", "timestamp": results_dir.name}

    if args.dry_run:
        metrics["perf"] = {
            "status": "dry_run",
            "prompt": args.prompt,
            "url": args.url,
        }
        _save_metrics(metrics, results_dir)
        print("[dry-run] perf test skipped (no server needed).")
        return metrics

    try:
        result = measure_streaming_ttft(
            prompt=args.prompt,
            url=args.url,
            system=args.system,
        )
        metrics["perf"] = result
        metrics["perf"]["status"] = "passed"
    except Exception as exc:  # noqa: BLE001
        metrics["perf"] = {"status": "failed", "error": str(exc)}

    _save_metrics(metrics, results_dir)
    print(f"[perf] TTFT={metrics['perf'].get('ttft_s', 'N/A'):.4f}s  "
          f"Toks/s={metrics['perf'].get('toks_per_s', 'N/A'):.2f}")
    return metrics


def run_soak(args: argparse.Namespace) -> dict[str, Any]:
    """Run a soak test by sampling free swap over *duration* seconds."""
    results_dir = _ensure_results_dir()
    metrics: dict[str, Any] = {"phase": "soak", "timestamp": results_dir.name}

    if args.dry_run:
        metrics["soak"] = {
            "status": "dry_run",
            "duration": args.duration,
        }
        _save_metrics(metrics, results_dir)
        print("[dry-run] soak test skipped.")
        return metrics

    try:
        start_free = _read_free_swap_mb()
        time.sleep(args.duration)
        end_free = _read_free_swap_mb()
        drift = calculate_drift(start_free, end_free)
        metrics["soak"] = {
            "status": "passed",
            "start_free_mb": start_free,
            "end_free_mb": end_free,
            "drift_mb": drift,
        }
    except Exception as exc:  # noqa: BLE001
        metrics["soak"] = {"status": "failed", "error": str(exc)}

    _save_metrics(metrics, results_dir)
    drift_val = metrics["soak"].get("drift_mb", "N/A")
    print(f"[soak] drift={drift_val:.2f} MB (positive=leak, negative=freed)")
    return metrics


def run_quality(args: argparse.Namespace) -> dict[str, Any]:
    """Run all polyglot quality tasks."""
    results_dir = _ensure_results_dir()
    metrics: dict[str, Any] = {"phase": "quality", "timestamp": results_dir.name}

    task_names = args.tasks if args.tasks else list(TASK_SCRIPTS.keys())
    results: list[dict[str, Any]] = []
    for name in task_names:
        if name not in TASK_SCRIPTS:
            print(f"[quality] unknown task '{name}', skipping.")
            continue
        print(f"[quality] running {name}...")
        results.append(_run_task(name, dry_run=args.dry_run))

    metrics["quality"] = {
        "tasks": results,
        "summary": {
            "total": len(results),
            "passed": sum(1 for r in results if r["status"] == "passed"),
            "failed": sum(1 for r in results if r["status"] == "failed"),
            "skipped": sum(1 for r in results if r["status"] in ("skipped", "dry_run")),
        },
    }
    _save_metrics(metrics, results_dir)
    print(f"[quality] done: {metrics['quality']['summary']}")
    return metrics


def run_all(args: argparse.Namespace) -> dict[str, Any]:
    """Execute perf, soak, and quality in sequence."""
    all_metrics: dict[str, Any] = {
        "phase": "all",
        "timestamp": None,
        "perf": None,
        "soak": None,
        "quality": None,
    }

    # --- perf ---
    perf_result = run_perf(args)
    all_metrics["perf"] = perf_result

    # --- soak ---
    soak_result = run_soak(args)
    all_metrics["soak"] = soak_result

    # --- quality ---
    quality_result = run_quality(args)
    all_metrics["quality"] = quality_result

    # Pick the most recent results_dir name for top-level timestamp
    all_metrics["timestamp"] = results_dir_name()

    # Save combined metrics
    combined_path = RESULTS_DIR / all_metrics["timestamp"] / "metrics.json"
    combined_path.parent.mkdir(parents=True, exist_ok=True)
    combined_path.write_text(json.dumps(all_metrics, indent=2, default=str))

    print(f"[all] combined metrics saved to {combined_path}")
    return all_metrics


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

def _read_free_swap_mb() -> float:
    """Return current free swap in MB by reading /proc/meminfo."""
    with open("/proc/meminfo", "r") as fh:
        for line in fh:
            if line.startswith("SwapFree:"):
                # Value is in kB
                return float(line.split()[1]) / 1024.0
    raise RuntimeError("SwapFree not found in /proc/meminfo")


def results_dir_name() -> str:
    """Return the name of the most recently created results sub-directory."""
    if not RESULTS_DIR.is_dir():
        return "unknown"
    dirs = sorted(RESULTS_DIR.iterdir(), key=lambda p: p.stat().st_mtime)
    return dirs[-1].name if dirs else "unknown"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    """Build the argument parser with subcommands."""
    parser = argparse.ArgumentParser(
        prog="run_suite",
        description="Berserker validation suite runner",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # -- perf --
    perf_p = subparsers.add_parser("perf", help="Streaming TTFT benchmark")
    perf_p.add_argument("--prompt", default="Say hello.", help="Prompt to send")
    perf_p.add_argument("--url", default="http://127.0.0.1:8080/v1/chat/completions",
                        help="LLM endpoint URL")
    perf_p.add_argument("--system", default="", help="System prompt")
    perf_p.add_argument("--dry-run", action="store_true", default=False,
                        help="Skip actual server call")

    # -- soak --
    soak_p = subparsers.add_parser("soak", help="Memory soak / leak detection")
    soak_p.add_argument("--duration", type=float, default=30,
                        help="Seconds to monitor swap")
    soak_p.add_argument("--dry-run", action="store_true", default=False,
                        help="Skip actual monitoring")

    # -- quality --
    qual_p = subparsers.add_parser("quality", help="Polyglot code quality tasks")
    qual_p.add_argument("--tasks", nargs="*", default=None,
                        help="Task names to run (default=all)")
    qual_p.add_argument("--dry-run", action="store_true", default=False,
                        help="Skip actual execution")

    # -- all --
    all_p = subparsers.add_parser("all",
                                  help="Run perf, soak, and quality in sequence")
    all_p.add_argument("--prompt", default="Say hello.", help="Prompt to send")
    all_p.add_argument("--url", default="http://127.0.0.1:8080/v1/chat/completions",
                       help="LLM endpoint URL")
    all_p.add_argument("--system", default="", help="System prompt")
    all_p.add_argument("--duration", type=float, default=30,
                       help="Soak duration in seconds")
    all_p.add_argument("--tasks", nargs="*", default=None,
                       help="Task names to run in quality phase (default=all)")
    all_p.add_argument("--dry-run", action="store_true", default=False,
                       help="Skip actual server calls and task execution")

    return parser


def main(argv: list[str] | None = None) -> int:
    """Entry point."""
    parser = build_parser()
    args = parser.parse_args(argv)

    dispatch = {
        "perf": run_perf,
        "soak": run_soak,
        "quality": run_quality,
        "all": run_all,
    }

    handler = dispatch.get(args.command)
    if handler is None:
        parser.print_help()
        return 1

    metrics = handler(args)
    # Print a one-line summary
    status = "passed"
    if isinstance(metrics.get("perf"), dict) and metrics["perf"].get("status") == "failed":
        status = "failed"
    if isinstance(metrics.get("soak"), dict) and metrics["soak"].get("status") == "failed":
        status = "failed"
    if isinstance(metrics.get("quality"), dict):
        summary = metrics["quality"].get("summary", {})
        if summary.get("failed", 0) > 0:
            status = "failed"

    print(f"[run_suite] phase={args.command}  status={status}")
    return 0 if status == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
