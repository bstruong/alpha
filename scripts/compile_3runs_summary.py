#!/usr/bin/env python3
"""Compiles 3-run statistical summary for Stone 1, 2, and 3 benchmarks."""
import json
import os
import statistics

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNS_DIR = os.path.join(PROJECT_ROOT, "reports", "runs")
REPORTS_DIR = os.path.join(PROJECT_ROOT, "reports")

MODELS = ["glm47-reap", "qwen36-coder-hybrid"]


def stats(values):
    return {
        "mean": round(statistics.mean(values), 2),
        "std_dev": round(statistics.stdev(values), 2) if len(values) > 1 else 0.0,
        "min": round(min(values), 2),
        "max": round(max(values), 2),
        "values": [round(v, 2) for v in values],
    }


def compile_summary():
    summary = {}
    for model in MODELS:
        m_data = {
            "model": model,
            "concurrency_solo_decode_tps": [],
            "concurrency_solo_ttft_sec": [],
            "concurrency_dual_aggregate_tps": [],
            "niah_16k_ttft_sec": [],
            "niah_16k_prefill_tps": [],
            "niah_32k_ttft_sec": [],
            "niah_32k_prefill_tps": [],
            "saber_passed": [],
            "saber_total": 138,
            "caster_turn1_passed": [],
            "caster_turn2_passed": [],
            "caster_total": 72,
        }

        for run_id in [1, 2, 3]:
            # 1. Concurrency
            cf = os.path.join(RUNS_DIR, f"concurrency_{model}_run_{run_id}.json")
            with open(cf) as f:
                c = json.load(f)
                m_data["concurrency_solo_decode_tps"].append(c["single_slot_baseline"]["decode_throughput_tps"])
                m_data["concurrency_solo_ttft_sec"].append(c["single_slot_baseline"]["ttft_sec"])
                m_data["concurrency_dual_aggregate_tps"].append(c["dual_slot_concurrent"]["aggregate_throughput_tps"])

            # 2. NIAH
            nf = os.path.join(RUNS_DIR, f"niah_{model}_run_{run_id}.json")
            with open(nf) as f:
                n = json.load(f)
                m_data["niah_16k_ttft_sec"].append(n["tests"][0]["ttft_sec"])
                m_data["niah_16k_prefill_tps"].append(n["tests"][0]["prefill_tps"])
                m_data["niah_32k_ttft_sec"].append(n["tests"][1]["ttft_sec"])
                m_data["niah_32k_prefill_tps"].append(n["tests"][1]["prefill_tps"])

            # 3. Repo coding
            rf = os.path.join(RUNS_DIR, f"repo_coding_{model}_run_{run_id}.json")
            with open(rf) as f:
                r = json.load(f)
                m_data["saber_passed"].append(r["saber"]["rspec"]["passed"])
                m_data["caster_turn1_passed"].append(r["caster"]["turn_1"]["rspec"]["passed"])
                t2 = r["caster"].get("turn_2")
                if t2 and "rspec" in t2:
                    m_data["caster_turn2_passed"].append(t2["rspec"]["passed"])
                else:
                    m_data["caster_turn2_passed"].append(r["caster"]["turn_1"]["rspec"]["passed"])

        summary[model] = {
            "model": model,
            "concurrency_solo_decode_tps": stats(m_data["concurrency_solo_decode_tps"]),
            "concurrency_solo_ttft_sec": stats(m_data["concurrency_solo_ttft_sec"]),
            "concurrency_dual_aggregate_tps": stats(m_data["concurrency_dual_aggregate_tps"]),
            "niah_16k_ttft_sec": stats(m_data["niah_16k_ttft_sec"]),
            "niah_16k_prefill_tps": stats(m_data["niah_16k_prefill_tps"]),
            "niah_32k_ttft_sec": stats(m_data["niah_32k_ttft_sec"]),
            "niah_32k_prefill_tps": stats(m_data["niah_32k_prefill_tps"]),
            "saber_all_runs_passed": all(p == 137 for p in m_data["saber_passed"]), # 137 pass + 1 pending = 138 total
            "saber_scores": m_data["saber_passed"],
            "caster_turn1_scores": m_data["caster_turn1_passed"],
            "caster_turn2_scores": m_data["caster_turn2_passed"],
            "caster_all_runs_resolved": all(p == 72 for p in m_data["caster_turn2_passed"]),
        }

    out_file = os.path.join(REPORTS_DIR, "runs", "stone_suite_3runs_summary.json")
    with open(out_file, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"Saved 3-run statistical summary to {out_file}")
    return summary


if __name__ == "__main__":
    compile_summary()
