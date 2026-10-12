#!/usr/bin/env python3
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from execute_common import (RESULTS_DIR, SANDBOX, MODELS, extract_code, load_run, sh,
                             git_reset, write_scores, runner_script, parse_result)

# D1: enqueue-after-commit awareness. We can't run a real job queue, but we can
# statically + dynamically check whether the enqueue call is wrapped in an
# after_commit-style deferral (7.2-safe pattern) or fires unconditionally inside
# the transaction body (naive pre-7.2 assumption).
def do_d1(code):
    uses_after_commit = bool(re.search(r"after_commit", code))
    # merge into Order model
    if "class Order" in code:
        file_content = code
    else:
        file_content = f"class Order < ApplicationRecord\n{code}\nend"
    with open(os.path.join(SANDBOX, "app", "models", "order.rb"), "w") as f:
        f.write(file_content)
    # OrderProcessorJob may not exist; stub it so loading doesn't NameError
    os.makedirs(os.path.join(SANDBOX, "app", "jobs"), exist_ok=True)
    with open(os.path.join(SANDBOX, "app", "jobs", "order_processor_job.rb"), "w") as f:
        f.write("class OrderProcessorJob < ApplicationJob\n  queue_as :default\n  def perform(order)\n  end\nend\n")
    check = runner_script("d1_check", '''
begin
  o = Order.new(status: "pending")
  ok = o.respond_to?(:process_order)
  puts "RESULT: #{ok ? "PASS" : "FAIL: no process_order method defined"}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-300:]}"
    detail = {"uses_after_commit": uses_after_commit, "runner_rc": rc, "out": out, "err": err[-800:]}
    git_reset()
    return rc == 0, behavior, detail, ("7.2-aware (defers via after_commit)" if uses_after_commit else "7.1-only (assumes immediate enqueue is safe)")

# D2: YJIT config snippet — no execution needed (config-only), score by static content.
def do_d2(code):
    mentions_yjit = bool(re.search(r"YJIT", code, re.IGNORECASE))
    mentions_default_on = bool(re.search(r"(already|default|enabled by default|Rails 7\.2)", code, re.IGNORECASE))
    version_note = "7.2-aware (notes YJIT is on by default)" if mentions_default_on else "7.1-only (manual enable, no mention of 7.2 default)"
    behavior = "PASS" if mentions_yjit else "FAIL: no YJIT reference found"
    detail = {"mentions_yjit": mentions_yjit, "mentions_default_on": mentions_default_on}
    return True, behavior, detail, version_note

# D3: Ruby minimum version check initializer — execute and inspect the version string used.
def do_d3(code):
    m = re.search(r"(\d+\.\d+(?:\.\d+)?)", code)
    stated_version = m.group(1) if m else None
    check = runner_script("d3_check", f'''
begin
{chr(10).join("  " + l for l in code.splitlines())}
  puts "RESULT: PASS"
rescue => e
  puts "RESULT: FAIL: exception loading initializer: #{{e.class}}: #{{e.message}}"
end
''')
    rc, out, err = sh(f"ruby {check}", cwd=RESULTS_DIR, timeout=15)
    behavior = parse_result(out) if rc == 0 else f"FAIL: ruby exited {rc}: {err.strip()[-300:]}"
    version_note = "unknown"
    if stated_version:
        if stated_version.startswith("3.1"):
            version_note = "7.2-aware (Ruby >= 3.1 floor)"
        elif stated_version.startswith(("2.7", "3.0")):
            version_note = "7.1-only (pre-7.2 Ruby floor)"
        else:
            version_note = f"other ({stated_version})"
    detail = {"stated_version": stated_version, "rc": rc, "out": out, "err": err[-500:]}
    return rc == 0, behavior, detail, version_note

# D4: after_commit / after_rollback callbacks on Order.
def do_d4(code):
    if "class Order" in code:
        file_content = code
    else:
        file_content = f"class Order < ApplicationRecord\n{code}\nend"
    with open(os.path.join(SANDBOX, "app", "models", "order.rb"), "w") as f:
        f.write(file_content)
    check = runner_script("d4_check", '''
begin
  callbacks = Order._commit_callbacks.map(&:filter) rescue []
  rollback_callbacks = Order._rollback_callbacks.map(&:filter) rescue []
  has_commit = !callbacks.empty?
  has_rollback = !rollback_callbacks.empty?
  ok = has_commit && has_rollback
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: has_commit_cb=#{has_commit} has_rollback_cb=#{has_rollback}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-300:]}"
    detail = {"runner_rc": rc, "out": out, "err": err[-800:]}
    git_reset()
    return rc == 0, behavior, detail, "n/a (after_commit/after_rollback predate 7.2)"

HANDLERS = {"D1": do_d1, "D2": do_d2, "D3": do_d3, "D4": do_d4}

def main():
    all_results = []
    for model in MODELS:
        for pid in ["D1", "D2", "D3", "D4"]:
            for run in (1, 2, 3):
                content = load_run(pid, model, run)
                code = extract_code(content)
                result = {"prompt": pid, "model": model, "run": run, "code_extracted": code is not None}
                if code is None:
                    result["executes"] = False
                    result["behavior"] = "FAIL: no code block found"
                    result["version_note"] = "unknown"
                else:
                    try:
                        executes, behavior, detail, version_note = HANDLERS[pid](code)
                        result["executes"] = executes
                        result["behavior"] = behavior
                        result["detail"] = detail
                        result["version_note"] = version_note
                    except Exception as e:
                        git_reset()
                        result["executes"] = False
                        result["behavior"] = f"FAIL: harness exception {type(e).__name__}: {e}"
                        result["version_note"] = "unknown"
                all_results.append(result)
                print(f"{model} {pid} run{run}: executes={result['executes']} behavior={result.get('behavior')} version={result.get('version_note')}")
    write_scores("scores_d.json", all_results)
    print("DONE category D")

if __name__ == "__main__":
    main()
