#!/usr/bin/env python3
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from execute_common import RESULTS_DIR, safe, MODELS

with open(os.path.join(RESULTS_DIR, "prompts.json")) as f:
    prompts = json.load(f)

scores = {}
for cat, fname in [("D", "scores_d.json"), ("E", "scores_e.json"), ("F", "scores_f.json"),
                    ("G", "scores_g.json"), ("H", "scores_h.json")]:
    with open(os.path.join(RESULTS_DIR, fname)) as f:
        for r in json.load(f):
            scores[(r["prompt"], r["model"], r["run"])] = r

out = []
out.append("# Round 2 Raw Output Appendix — Direct Ruby/Rails Model Benchmark\n")
out.append(f"Generated {os.popen('date').read().strip()}\n")

for pid in sorted(prompts.keys()):
    pdata = prompts[pid]
    out.append(f"\n---\n## {pid} (Category {pdata['category']})\n")
    out.append(f"**Prompt:** {pdata['text']}\n")
    for model in MODELS:
        for run in (1, 2, 3):
            path = os.path.join(RESULTS_DIR, "raw", pid, safe(model), f"run{run}.json")
            with open(path) as f:
                body = json.load(f)
            content = body.get("message", {}).get("content", "")
            key = (pid, model, run)
            score_line = ""
            if key in scores:
                r = scores[key]
                extras = []
                if "idiom" in r:
                    extras.append(f"idiom={r['idiom']}")
                if "version_note" in r:
                    extras.append(f"version={r['version_note']}")
                if "hallucinated_api" in r and r["hallucinated_api"]:
                    extras.append(f"HALLUCINATED={r['hallucinated_api']}")
                if "false_positive" in r:
                    extras.append(f"false_positive={r['false_positive']}")
                extra_str = " | " + " | ".join(extras) if extras else ""
                score_line = f" | executes={r.get('executes')} | behavior={r.get('behavior')}{extra_str}"
            out.append(f"\n### {model} — run {run}{score_line}\n")
            out.append("```\n" + content.strip() + "\n```\n")

with open(os.path.join(RESULTS_DIR, "APPENDIX_ROUND2.md"), "w") as f:
    f.write("\n".join(out))
print("wrote APPENDIX_ROUND2.md")
