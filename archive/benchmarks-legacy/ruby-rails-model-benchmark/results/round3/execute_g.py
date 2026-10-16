#!/usr/bin/env python3
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from execute_common import (RESULTS_DIR, SANDBOX, MODELS, extract_code, load_run, sh,
                             git_reset, write_scores)

REFS = os.path.join(RESULTS_DIR, "references")
SUMMARY_RE = re.compile(r"(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips")

def parse_summary(out):
    m = SUMMARY_RE.search(out)
    if not m:
        return None
    runs, assertions, failures, errors, skips = map(int, m.groups())
    return {"runs": runs, "assertions": assertions, "failures": failures, "errors": errors, "skips": skips}

def apply_posts_scaffold(variant):
    with open(os.path.join(REFS, f"posts_controller_{variant}.rb")) as f:
        controller = f.read()
    with open(os.path.join(SANDBOX, "app", "controllers", "posts_controller.rb"), "w") as f:
        f.write(controller)
    routes_path = os.path.join(SANDBOX, "config", "routes.rb")
    with open(routes_path) as f:
        routes = f.read()
    if "member { match :publish" not in routes:
        new_routes = routes.replace(
            "Rails.application.routes.draw do",
            "Rails.application.routes.draw do\n  resources :posts, only: [:show] do\n    member { match :publish, via: [:get, :post, :patch, :put] }\n  end"
        )
        with open(routes_path, "w") as f:
            f.write(new_routes)

def apply_user_scaffold(variant):
    with open(os.path.join(REFS, f"user_{variant}.rb")) as f:
        content = f.read()
    with open(os.path.join(SANDBOX, "app", "models", "user.rb"), "w") as f:
        f.write(content)

def run_generated_test(test_code, test_path, run_path_rel):
    with open(test_path, "w") as f:
        f.write(test_code)
    rc, out, err = sh(f"bin/rails test {run_path_rel}", timeout=60)
    summary = parse_summary(out)
    return rc, out, err, summary

def do_g(pid, code, apply_fn, test_dir, test_filename):
    test_path = os.path.join(SANDBOX, test_dir, test_filename)
    run_path_rel = f"{test_dir}/{test_filename}"

    # 1. against correct reference implementation
    apply_fn("correct")
    rc1, out1, err1, summary1 = run_generated_test(code, test_path, run_path_rel)
    passes_correct = bool(summary1) and summary1["runs"] > 0 and summary1["failures"] == 0 and summary1["errors"] == 0
    git_reset()

    # 2. against deliberately-broken reference implementation (re-apply test file, it was wiped by git_reset)
    apply_fn("broken")
    rc2, out2, err2, summary2 = run_generated_test(code, test_path, run_path_rel)
    passes_broken = bool(summary2) and summary2["runs"] > 0 and summary2["failures"] == 0 and summary2["errors"] == 0
    git_reset()

    well_formed = summary1 is not None and summary1["runs"] > 0
    false_positive = passes_correct and passes_broken  # worse failure class: green on broken code too

    if not well_formed:
        behavior = f"FAIL: test malformed / did not run (rc={rc1}): {err1.strip()[-300:] or out1.strip()[-300:]}"
    elif false_positive:
        behavior = "FAIL: FALSE POSITIVE — test passes against BOTH correct and deliberately-broken implementations (does not actually test the behavior)"
    elif passes_correct and not passes_broken:
        behavior = "PASS: correctly passes against correct implementation and fails against broken implementation"
    elif not passes_correct:
        behavior = f"FAIL: does not pass even against the correct reference implementation ({summary1})"
    else:
        behavior = f"FAIL: unexpected combination correct={passes_correct} broken={passes_broken}"

    detail = {
        "summary_vs_correct": summary1, "summary_vs_broken": summary2,
        "out_vs_correct": out1[-1500:], "out_vs_broken": out2[-1500:],
    }
    return well_formed, behavior, detail, passes_correct, passes_broken

def main():
    all_results = []
    for model in MODELS:
        for pid, apply_fn, test_dir, fname in [
            ("G1", apply_posts_scaffold, "test/integration", "bench_g1_generated_test.rb"),
            ("G2", apply_user_scaffold, "test/models", "bench_g2_generated_test.rb"),
        ]:
            for run in (1, 2, 3):
                content = load_run(pid, model, run)
                code = extract_code(content)
                result = {"prompt": pid, "model": model, "run": run, "code_extracted": code is not None}
                if code is None:
                    result["executes"] = False
                    result["behavior"] = "FAIL: no code block found"
                else:
                    try:
                        well_formed, behavior, detail, passes_correct, passes_broken = do_g(pid, code, apply_fn, test_dir, fname)
                        result["executes"] = well_formed
                        result["behavior"] = behavior
                        result["detail"] = detail
                        result["passes_correct_impl"] = passes_correct
                        result["passes_broken_impl"] = passes_broken
                        result["false_positive"] = passes_correct and passes_broken
                    except Exception as e:
                        git_reset()
                        result["executes"] = False
                        result["behavior"] = f"FAIL: harness exception {type(e).__name__}: {e}"
                all_results.append(result)
                print(f"{model} {pid} run{run}: executes={result['executes']} behavior={result.get('behavior')}")
    write_scores("scores_g.json", all_results)
    print("DONE category G")

if __name__ == "__main__":
    main()
