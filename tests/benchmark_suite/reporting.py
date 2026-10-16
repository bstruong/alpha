"""Shared report I/O for independently runnable benchmark modules."""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone

from tests.benchmark_suite.common import FLASH_MODEL, SEED
from tests.benchmark_suite.spec_traps.test_spec_traps import trap_passed

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REPORTS_DIR = os.path.join(PROJECT_ROOT, "reports")
FULL_JSON = os.path.join(REPORTS_DIR, "frontier_full_eval.json")
SCORECARD_MD = os.path.join(REPORTS_DIR, "FRONTIER_EVAL_SCORECARD.md")

MODULE_JSON = {
    "telemetry": os.path.join(REPORTS_DIR, "module1_telemetry.json"),
    "spec_traps": os.path.join(REPORTS_DIR, "module2_spec_traps.json"),
    "pipeline": os.path.join(REPORTS_DIR, "module3_pipeline.json"),
}


def harness_metadata() -> dict:
    return {
        "version": 3,
        "request_knobs": {"temperature": 0, "seed": SEED, "cache_prompt": False},
        "flash_model_id": FLASH_MODEL,
        "improvements": [
            "independent_modules",
            "reproducible_request_knobs",
            "slot_erase_between_modules_and_traps",
            "execution_oracle_test_a_b",
            "soft_test_c_scratchpad",
            "per_trap_metrics",
            "grade_content_and_reasoning",
            "soften_test_a_code_only_float_ban",
            "persist_responses",
            "planner_retry_on_empty_phase",
            "pipeline_failure_reason",
            "telemetry_primary_2k_8k",
            "test_c_named_deliverables_retry",
            "planner_token_cap",
        ],
    }


def load_full_results() -> dict:
    if not os.path.isfile(FULL_JSON):
        return {"harness": harness_metadata()}
    with open(FULL_JSON, encoding="utf-8") as f:
        data = json.load(f)
    data.setdefault("harness", harness_metadata())
    return data


def save_module_result(module_key: str, payload: dict) -> str:
    """Write per-module JSON and merge into frontier_full_eval.json + scorecard."""
    os.makedirs(REPORTS_DIR, exist_ok=True)
    module_path = MODULE_JSON[module_key]
    with open(module_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)

    full = load_full_results()
    full["harness"] = harness_metadata()
    full[module_key] = payload
    full.setdefault("modules_updated", {})[module_key] = datetime.now(timezone.utc).isoformat()
    with open(FULL_JSON, "w", encoding="utf-8") as f:
        json.dump(full, f, indent=2)

    generate_markdown_report(full, SCORECARD_MD)
    print(f"Saved module results to {module_path}", flush=True)
    print(f"Merged into {FULL_JSON}", flush=True)
    print(f"Updated scorecard {SCORECARD_MD}", flush=True)
    return module_path


def generate_markdown_report(results: dict, report_path: str) -> None:
    telemetry = results.get("telemetry") or {}
    spec_traps = results.get("spec_traps") or {}
    pipeline = results.get("pipeline") or {}
    updated = results.get("modules_updated") or {}

    def cell(data: dict, key: str, default="N/A"):
        if not data or "error" in data:
            return default if key != "error" else "ERROR"
        return data.get(key, default)

    md = f"""# Frontier Model Evaluation Scorecard
**Date:** {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}
**Hardware Target:** Workstation (AMD Ryzen 7 9700X, RTX 3060 12GB, 32GB RAM, Samsung 990 Pro NVMe)
**Harness:** v3+ — independent modules; temp 0 / seed {SEED} / no prompt cache; slot erase; oracles A/B; soft Test C; primary telemetry 2k/8k; Test C named deliverables+retry; planner token cap
**Modules last updated:** telemetry={updated.get('telemetry', 'never')} · spec_traps={updated.get('spec_traps', 'never')} · pipeline={updated.get('pipeline', 'never')}

## 1. Hardware Throughput Matrix
"""
    if not _has_module(telemetry, ("2000", "8000", "32000", "64000", 2000, 8000, 32000, 64000)):
        if telemetry.get("error"):
            md += f"_Telemetry error: {telemetry['error']}_\n\n"
        else:
            md += "_Not run yet. Execute `python3 scripts/run_module1_telemetry.py`._\n\n"
    else:
        md += """
| Context Size | TTFT (s) | Prefill (t/s) | Decode (t/s) | Peak RAM (MB) | Peak VRAM (MB) |
|--------------|----------|---------------|--------------|---------------|----------------|
"""
        for size in ["2000", "8000", "32000", "64000"]:
            data = telemetry.get(size, telemetry.get(int(size), {}))
            size_label = size
            # Annotate long-context rows as secondary (NVMe-bound) when flagged or by size.
            if int(size) >= 32000 or (isinstance(data, dict) and data.get("nvme_bound")):
                size_label = f"{size}†"
            elif isinstance(data, dict) and data.get("primary") is True:
                size_label = f"{size}*"
            if not data:
                md += f"| {size_label} | — | — | — | — | — |\n"
            elif "error" in data:
                md += f"| {size_label} | ERROR | ERROR | ERROR | {data.get('peak_ram_mb', 'N/A')} | {data.get('peak_vram_mb', 'N/A')} |\n"
            else:
                md += (
                    f"| {size_label} | {cell(data, 'ttft_sec')} | {cell(data, 'prefill_throughput_tps')} | "
                    f"{cell(data, 'decode_throughput_tps')} | {cell(data, 'peak_ram_mb')} | "
                    f"{cell(data, 'peak_vram_mb')} |\n"
                )
        md += (
            "\n\\* Primary regression metrics: 2k/8k. "
            "† 32k/64k decode is NVMe-bound (secondary signal only).\n\n"
        )

    md += "## 2. Cognitive Spec Trap Pass/Fail Rates\n\n"
    if not _has_module(spec_traps, ("Test_A", "Test_B", "Test_C")):
        md += "_Not run yet. Execute `python3 scripts/run_module2_spec_traps.py`._\n\n"
    else:
        md += f"""| Test | Description | Result |
|------|-------------|--------|
| **Test A** | Precision Guard (decimal.Decimal vs float) | {'✅ PASS' if trap_passed(spec_traps.get('Test_A')) else '❌ FAIL'} |
| **Test B** | Multi-File Dependency Consistency | {'✅ PASS' if trap_passed(spec_traps.get('Test_B')) else '❌ FAIL'} |
| **Test C** | Code deliverable (scratchpad ≤ 5 bullets is a soft flag) | {'✅ PASS' if trap_passed(spec_traps.get('Test_C')) else '❌ FAIL'} |

"""

    md += "## 3. Two-Model Pipeline Latency & Handoff Quality Score\n\n"
    pipeline_updated = updated.get("pipeline")
    if not _has_module(pipeline, ("swap_latency_sec", "worker_time_sec", "worker_success", "planner_chars")):
        if pipeline.get("error"):
            md += f"_Pipeline error: {pipeline['error']}_\n\n"
        else:
            md += "_Not run yet. Execute `python3 scripts/run_module3_pipeline.py` (needs router mode)._\n\n"
    elif not pipeline_updated:
        md += (
            "_Stale — retained from a prior Module 3 run; not refreshed this session "
            f"(header: pipeline=never). Re-run `python3 scripts/run_module3_pipeline.py` to update._\n\n"
        )
        md += _pipeline_section(pipeline)
    else:
        md += _pipeline_section(pipeline)

    md += """### Notes
- Run modules independently; each merges into `reports/frontier_full_eval.json` without wiping other modules.
- Per-trap metrics and response previews live in the JSON / `reports/moduleN_*.json`.
- Flash-Next uses mmap (required on 32GB); Tier-1 worker uses mlock/cpu-moe when memlock allows.
"""
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(md)


def _has_module(data: dict, keys) -> bool:
    return bool(data) and any(k in data for k in keys)


def _pipeline_section(pipeline: dict) -> str:
    return f"""- **Model Swap Latency (100B+ -> 35B):** {pipeline.get('swap_latency_sec', 'N/A')} seconds
- **Worker Execution Time:** {pipeline.get('worker_time_sec', 'N/A')} seconds
- **Worker Execution Success (Under 15s):** {'✅ PASS' if pipeline.get('worker_success') else '❌ FAIL'}
- **Failure Reason:** {pipeline.get('failure_reason') or 'none'}
- **Planner / Phase 1.1 chars:** {pipeline.get('planner_chars', 'N/A')} / {pipeline.get('phase_1_1_chars', 'N/A')}

- **Planner metrics:** {pipeline.get('planner_metrics', 'N/A')}
- **Worker metrics:** {pipeline.get('worker_metrics', 'N/A')}

### Handoff Quality Score
Overall Pipeline Status: **{'✅ HEALTHY' if pipeline.get('worker_success') else '❌ DEGRADED'}**

"""


def require_server() -> None:
    import os
    import requests

    health_url = os.getenv("ALPHA_HEALTH_URL") or (os.getenv("LLAMA_SERVER_URL", "http://192.168.1.92:8080").rstrip("/") + "/health")
    try:
        r = requests.get(health_url, timeout=3)
        if r.status_code != 200:
            raise RuntimeError(f"/health -> {r.status_code}")
    except Exception as e:
        raise SystemExit(
            f"llama-server not healthy at {health_url} ({e}).\n"
            "Please verify Watchtower service status:\n"
            "  ssh watchtower systemctl --user status alpha-llama.service\n"
        ) from e

