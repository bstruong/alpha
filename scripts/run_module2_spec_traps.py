#!/usr/bin/env python3
"""Module 2 — Cognitive Spec Traps (independent).

Runs Tests A/B/C against Flash with execution oracles (A/B) and soft Test C.

  python3 scripts/run_module2_spec_traps.py

Requires llama-server on :8080. BENCH_MODEL overrides the default Flash id.
"""
import os
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from tests.benchmark_suite.common import FLASH_MODEL, erase_slots
from tests.benchmark_suite.reporting import require_server, save_module_result
from tests.benchmark_suite.spec_traps.test_spec_traps import run_all_spec_traps


def main() -> None:
    require_server()
    erase_slots(os.environ.get("BENCH_MODEL", FLASH_MODEL), label="module2 start")
    print("--- Module 2: Cognitive Spec Traps ---", flush=True)
    try:
        results = run_all_spec_traps()
    except Exception as e:
        print(f"Module 2 failed: {e}", flush=True)
        results = {"error": str(e)}
    save_module_result("spec_traps", results)


if __name__ == "__main__":
    main()
