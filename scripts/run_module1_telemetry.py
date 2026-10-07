#!/usr/bin/env python3
"""Module 1 — Hardware & Telemetry (independent).

Measures TTFT / prefill / decode / peak RAM+VRAM at 2k–64k context on Flash.

  python3 scripts/run_module1_telemetry.py

Requires llama-server on :8080 with Flash available (router or single).
"""
import os
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from tests.benchmark_suite.reporting import require_server, save_module_result
from tests.benchmark_suite.telemetry.test_hardware_limits import run_hardware_limits_benchmark


def main() -> None:
    require_server()
    print("--- Module 1: Hardware & Telemetry ---", flush=True)
    try:
        results = run_hardware_limits_benchmark()
    except Exception as e:
        print(f"Module 1 failed: {e}", flush=True)
        results = {"error": str(e)}
    save_module_result("telemetry", results)


if __name__ == "__main__":
    main()
