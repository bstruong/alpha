#!/usr/bin/env python3
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from execute_common import (RESULTS_DIR, MODELS, extract_code, load_run, sh, write_scores)

PROMPT_IDS = ["A1", "A2", "A3", "A4"]
TMP_RB = "/home/brian/benchmarks/results/tmp_a.rb"

def run_one(prompt_id, model, run):
    content = load_run(prompt_id, model, run)
    code = extract_code(content)
    result = {"prompt": prompt_id, "model": model, "run": run,
              "code_extracted": code is not None,
              "raw_chars": len(content)}
    if code is None:
        result["executes"] = False
        result["behavior"] = "FAIL: no code block found in output"
        return result

    driver_path = os.path.join(RESULTS_DIR, "drivers", f"{prompt_id.lower()}_driver.rb")
    with open(driver_path) as f:
        driver = f.read()

    with open(TMP_RB, "w") as f:
        f.write(code + "\n\n" + driver)

    rc, out, err = sh(f"ruby {TMP_RB}", cwd="/home/brian/benchmarks/results", timeout=15)
    result["exit_code"] = rc
    result["stdout"] = out.strip()
    result["stderr"] = err.strip()[-2000:]

    if rc != 0:
        result["executes"] = False
        result["behavior"] = f"FAIL: ruby exited {rc}"
    else:
        result["executes"] = True
        if "RESULT: PASS" in out:
            result["behavior"] = "PASS"
        elif "RESULT: FAIL" in out:
            # extract the FAIL line
            fail_line = [l for l in out.splitlines() if l.startswith("RESULT: FAIL")]
            result["behavior"] = fail_line[0] if fail_line else "FAIL"
        else:
            result["behavior"] = "FAIL: driver produced no RESULT line"
    return result

def main():
    all_results = []
    for model in MODELS:
        for pid in PROMPT_IDS:
            for run in (1, 2, 3):
                r = run_one(pid, model, run)
                all_results.append(r)
                print(f"{model} {pid} run{run}: executes={r['executes']} behavior={r.get('behavior')}")
    write_scores("scores_a.json", all_results)
    print("DONE category A")

if __name__ == "__main__":
    main()
