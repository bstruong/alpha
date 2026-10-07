#!/usr/bin/env python3
"""Module 3 — Planner / Worker Pipeline (independent).

Flash planner → Tier-1 (qwen36-coder) worker; measures swap latency + worker SLA.

  python3 scripts/run_module3_pipeline.py

Requires llama-server in *router* mode with both Flash and qwen36-coder registered.
"""
import os
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from tests.benchmark_suite.common import FLASH_MODEL, erase_slots
from tests.benchmark_suite.pipeline.test_two_model_handoff import run_pipeline_benchmark
from tests.benchmark_suite.reporting import require_server, save_module_result


def main() -> None:
    require_server()
    erase_slots(FLASH_MODEL, label="module3 start")
    print("--- Module 3: Planner / Worker Pipeline ---", flush=True)
    try:
        results = run_pipeline_benchmark()
    except Exception as e:
        print(f"Module 3 failed: {e}", flush=True)
        results = {"error": str(e)}
    save_module_result("pipeline", results)


if __name__ == "__main__":
    main()
