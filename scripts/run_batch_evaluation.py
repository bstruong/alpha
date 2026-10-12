#!/usr/bin/env python3
"""Batch runner for repeated Berserker benchmark iterations.

Runs Module 1 (Hardware & Telemetry) and Module 2 (Cognitive Spec Traps)
for a given model across a range of run indices, archiving per-run outputs
to reports/runs/{model}_run_{i}.json.
"""
import argparse
import json
import os
import subprocess
import sys
import time

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPORTS_DIR = os.path.join(PROJECT_ROOT, "reports")
RUNS_DIR = os.path.join(REPORTS_DIR, "runs")


def run_command(cmd, env):
    start = time.time()
    proc = subprocess.run(cmd, env=env, text=True, capture_output=False)
    elapsed = time.time() - start
    if proc.returncode != 0:
        raise RuntimeError(f"Command {' '.join(cmd)} failed with exit code {proc.returncode} in {elapsed:.2f}s")
    return elapsed


def main():
    parser = argparse.ArgumentParser(description="Run repeated benchmark iterations.")
    parser.add_argument("--model", required=True, help="Model preset/ID (e.g., glm47-reap, qwen36-coder)")
    parser.add_argument("--start-run", type=int, default=1, help="Starting run index")
    parser.add_argument("--end-run", type=int, default=3, help="Ending run index (inclusive)")
    args = parser.parse_args()

    os.makedirs(RUNS_DIR, exist_ok=True)
    base_env = os.environ.copy()
    base_env["BENCHMARK_MODEL"] = args.model
    base_env["BENCH_MODEL"] = args.model
    base_env["PYTHONUNBUFFERED"] = "1"

    print(f"\n=======================================================", flush=True)
    print(f" Starting Batch Evaluation for {args.model}: Runs {args.start_run} to {args.end_run}", flush=True)
    print(f"=======================================================\n", flush=True)

    for run_idx in range(args.start_run, args.end_run + 1):
        print(f"\n>>> [{args.model}] Starting Run {run_idx}/{args.end_run} <<<", flush=True)
        run_start = time.time()

        # Run Module 1
        print(f"\n--- [{args.model} Run {run_idx}] Executing Module 1: Telemetry ---", flush=True)
        m1_cmd = [sys.executable, os.path.join(PROJECT_ROOT, "scripts", "run_module1_telemetry.py")]
        m1_time = run_command(m1_cmd, base_env)

        with open(os.path.join(REPORTS_DIR, "module1_telemetry.json")) as f:
            m1_data = json.load(f)

        # Run Module 2
        print(f"\n--- [{args.model} Run {run_idx}] Executing Module 2: Spec Traps ---", flush=True)
        m2_cmd = [sys.executable, os.path.join(PROJECT_ROOT, "scripts", "run_module2_spec_traps.py")]
        m2_time = run_command(m2_cmd, base_env)

        with open(os.path.join(REPORTS_DIR, "module2_spec_traps.json")) as f:
            m2_data = json.load(f)

        total_run_time = time.time() - run_start
        run_record = {
            "run": run_idx,
            "model": args.model,
            "timestamp": time.time(),
            "wall_sec_total": round(total_run_time, 2),
            "m1_wall_sec": round(m1_time, 2),
            "m2_wall_sec": round(m2_time, 2),
            "telemetry": m1_data,
            "spec_traps": m2_data,
        }

        output_file = os.path.join(RUNS_DIR, f"{args.model}_run_{run_idx}.json")
        with open(output_file, "w") as f:
            json.dump(run_record, f, indent=2)

        print(f"\n>>> [{args.model}] Run {run_idx} Complete in {total_run_time:.2f}s. Saved to {output_file} <<<\n", flush=True)

    print(f"\n=======================================================", flush=True)
    print(f" Batch Evaluation Completed for {args.model}", flush=True)
    print(f"=======================================================\n", flush=True)


if __name__ == "__main__":
    main()
