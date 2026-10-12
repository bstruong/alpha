#!/usr/bin/env python3
"""Automated Multi-Run Execution Harness for 4-Stone LLM Evaluation.

Executes Stone 1 (Concurrency), Stone 3 (NIAH), and Stone 2 (Real Repos) across multiple runs.
"""
import argparse
import os
import subprocess
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run_stone_suite_for_run(model: str, run_id: int):
    print(f"\n=======================================================", flush=True)
    print(f" STARTING MULTI-RUN EXECUTION: Model {model} | RUN {run_id}", flush=True)
    print(f"=======================================================\n", flush=True)

    # Stone 1: Concurrency
    print(f"\n>>> [Run {run_id}] Executing Stone 1 (Concurrency) for {model} <<<", flush=True)
    cmd1 = f"python3 {os.path.join(PROJECT_ROOT, 'scripts/bench_concurrency.py')} --model {model} --run {run_id}"
    subprocess.run(cmd1, shell=True, check=True, cwd=PROJECT_ROOT)

    # Stone 3: NIAH
    print(f"\n>>> [Run {run_id}] Executing Stone 3 (NIAH 16k & 32k) for {model} <<<", flush=True)
    cmd3 = f"python3 {os.path.join(PROJECT_ROOT, 'scripts/bench_needle_haystack.py')} --model {model} --run {run_id} --contexts 16000 32000"
    subprocess.run(cmd3, shell=True, check=True, cwd=PROJECT_ROOT)

    # Stone 2: Real Repos
    print(f"\n>>> [Run {run_id}] Executing Stone 2 (Real Repos: Saber & Caster) for {model} <<<", flush=True)
    cmd2 = f"python3 {os.path.join(PROJECT_ROOT, 'scripts/bench_real_repos.py')} --model {model} --run {run_id}"
    subprocess.run(cmd2, shell=True, check=True, cwd=PROJECT_ROOT)

    print(f"\n>>> FINISHED RUN {run_id} FOR {model} <<<\n", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Multi-run Stone Evaluator")
    parser.add_argument("--model", required=True)
    parser.add_argument("--runs", nargs="+", type=int, default=[2, 3])
    args = parser.parse_args()

    for r in args.runs:
        run_stone_suite_for_run(args.model, r)


if __name__ == "__main__":
    main()
