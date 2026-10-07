#!/usr/bin/env python3
"""Run all three frontier benchmark modules in sequence (optional convenience).

Prefer independent entrypoints when iterating:

  python3 scripts/run_module1_telemetry.py
  python3 scripts/run_module2_spec_traps.py
  python3 scripts/run_module3_pipeline.py

This script only chains them with slot erase between modules.
"""
import os
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from tests.benchmark_suite.common import FLASH_MODEL, SEED, erase_slots
from tests.benchmark_suite.pipeline.test_two_model_handoff import run_pipeline_benchmark
from tests.benchmark_suite.reporting import require_server, save_module_result
from tests.benchmark_suite.spec_traps.test_spec_traps import run_all_spec_traps
from tests.benchmark_suite.telemetry.test_hardware_limits import run_hardware_limits_benchmark


def main() -> None:
    require_server()
    print("Starting Frontier Model Evaluation Benchmark Suite...", flush=True)
    print(
        f"Harness v3 (seed {SEED}): independent modules chained; slot erase between modules",
        flush=True,
    )

    print("\n--- Running Module 1: Hardware & Telemetry ---", flush=True)
    try:
        save_module_result("telemetry", run_hardware_limits_benchmark())
    except Exception as e:
        print(f"Module 1 failed: {e}", flush=True)
        save_module_result("telemetry", {"error": str(e)})

    erase_slots(FLASH_MODEL, label="module 1 -> 2")
    print("\n--- Running Module 2: Cognitive Spec Traps ---", flush=True)
    try:
        save_module_result("spec_traps", run_all_spec_traps())
    except Exception as e:
        print(f"Module 2 failed: {e}", flush=True)
        save_module_result("spec_traps", {"error": str(e)})

    erase_slots(FLASH_MODEL, label="module 2 -> 3")
    print("\n--- Running Module 3: Planner / Worker Pipeline ---", flush=True)
    try:
        save_module_result("pipeline", run_pipeline_benchmark())
    except Exception as e:
        print(f"Module 3 failed: {e}", flush=True)
        save_module_result("pipeline", {"error": str(e)})

    print("\nFull suite finished. See reports/FRONTIER_EVAL_SCORECARD.md", flush=True)


if __name__ == "__main__":
    main()
