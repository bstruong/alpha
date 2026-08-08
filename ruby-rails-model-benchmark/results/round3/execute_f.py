#!/usr/bin/env python3
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from execute_common import (RESULTS_DIR, SANDBOX, MODELS, extract_code, extract_all_code, load_run, sh,
                             git_reset, write_scores, runner_script, parse_result)

def write_model(name, code_for_class):
    path = os.path.join(SANDBOX, "app", "models", f"{name.lower()}.rb")
    if f"class {name}" in code_for_class:
        content = code_for_class
    else:
        content = f"class {name} < ApplicationRecord\n{code_for_class}\nend"
    with open(path, "w") as f:
        f.write(content)

# ---------- F1: has_many :through (Doctor/Patient/Appointment) ----------
def do_f1(code):
    blocks = extract_all_code(code) or [code]
    combined = "\n\n".join(blocks)
    for name in ["Doctor", "Patient", "Appointment"]:
        m = re.search(rf"class\s+{name}\b.*?(?=\nclass\s+\w|\Z)", combined, re.DOTALL)
        if m:
            write_model(name, m.group(0))
    check = runner_script("f1_check", '''
begin
  d = Doctor.create!(name: "Dr. A")
  p1 = Patient.create!(name: "P1")
  Appointment.create!(doctor: d, patient: p1, scheduled_at: Time.current)
  ok = d.respond_to?(:patients) && d.patients.include?(p1)
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: respond_to_patients=#{d.respond_to?(:patients)} includes=#{d.respond_to?(:patients) ? d.patients.include?(p1) : "n/a"}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-400:]}"
    detail = {"rc": rc, "out": out, "err": err[-800:]}
    git_reset()
    return rc == 0, behavior, detail

# ---------- F2: polymorphic Comment ----------
def do_f2(code):
    blocks = extract_all_code(code) or [code]
    combined = "\n\n".join(blocks)
    m = re.search(r"class\s+Comment\b.*?(?=\nclass\s+\w|\Z)", combined, re.DOTALL)
    if m:
        write_model("Comment", m.group(0))
    has_comments_line = re.search(r"has_many\s+:comments.*as:\s*:commentable", combined)
    for name in ["Article", "Post"]:
        path = os.path.join(SANDBOX, "app", "models", f"{name.lower()}.rb")
        with open(path) as f:
            existing = f.read()
        if has_comments_line and "has_many :comments" not in existing:
            new_content = existing.replace(f"class {name} < ApplicationRecord",
                                            f"class {name} < ApplicationRecord\n  has_many :comments, as: :commentable")
            with open(path, "w") as f:
                f.write(new_content)
    check = runner_script("f2_check", '''
begin
  a = Article.create!(title: "T", body: "B")
  c = Comment.create!(body: "nice", commentable: a)
  ok = a.respond_to?(:comments) && a.comments.include?(c)
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: respond_to=#{a.respond_to?(:comments)} includes=#{a.respond_to?(:comments) ? a.comments.include?(c) : "n/a"}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-400:]}"
    detail = {"rc": rc, "out": out, "err": err[-800:], "has_comments_line_found": bool(has_comments_line)}
    git_reset()
    return rc == 0, behavior, detail

# ---------- F3: Order shipped_at callback, correct timing ----------
def do_f3(code):
    write_model("Order", code)
    check = runner_script("f3_check", '''
begin
  o = Order.create!(status: "pending")
  o.update!(status: "shipped")
  ts1 = o.reload.shipped_at
  set_on_transition = !ts1.nil?

  sleep 0.05
  o.update!(status: "shipped")  # no actual change (already shipped) -- should be a no-op save
  ts2 = o.reload.shipped_at
  stable_on_noop = (ts1 == ts2)

  ok = set_on_transition && stable_on_noop
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: set_on_transition=#{set_on_transition} stable_on_noop=#{stable_on_noop} ts1=#{ts1.inspect} ts2=#{ts2.inspect}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-400:]}"
    detail = {"rc": rc, "out": out, "err": err[-800:]}
    git_reset()
    return rc == 0, behavior, detail

# ---------- F4: Archivable Concern ----------
def do_f4(code):
    blocks = extract_all_code(code) or [code]
    combined = "\n\n".join(blocks)
    m = re.search(r"module\s+(\w+)\b.*?(?=\nmodule\s+\w|\Z)", combined, re.DOTALL)
    module_name = None
    if m:
        module_name = m.group(1)
        os.makedirs(os.path.join(SANDBOX, "app", "models", "concerns"), exist_ok=True)
        concern_path = os.path.join(SANDBOX, "app", "models", "concerns", f"{re.sub('([a-z0-9])([A-Z])', r'\\1_\\2', module_name).lower()}.rb")
        with open(concern_path, "w") as f:
            f.write(m.group(0))
    for name in ["Article", "Order"]:
        path = os.path.join(SANDBOX, "app", "models", f"{name.lower()}.rb")
        with open(path) as f:
            existing = f.read()
        if module_name and f"include {module_name}" not in existing:
            new_content = existing.replace(f"class {name} < ApplicationRecord",
                                            f"class {name} < ApplicationRecord\n  include {module_name}")
            with open(path, "w") as f:
                f.write(new_content)
    check = runner_script("f4_check", '''
begin
  a = Article.create!(title: "T", body: "B")
  a.archive!
  active_excludes = Article.active.exclude?(a) rescue nil
  ok = a.reload.archived == true && active_excludes == true
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: archived=#{a.reload.archived} active_excludes=#{active_excludes}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-400:]}"
    detail = {"rc": rc, "out": out, "err": err[-800:], "module_name": module_name}
    git_reset()
    return rc == 0, behavior, detail

# ---------- F5: strong params for nested attributes ----------
def do_f5(code):
    m = re.search(r"params\s*\.\s*require\([^)]*\)\s*\.\s*permit\(.*?\)", code, re.DOTALL)
    permit_over = bool(re.search(r"permit!", code))
    if not m and not permit_over:
        git_reset()
        return False, "FAIL: could not extract a params.require(...).permit(...) expression", {"raw": code[:500]}
    expr = "params.permit!" if permit_over else m.group(0)
    check = runner_script("f5_check", f'''
begin
  params = ActionController::Parameters.new(
    article: {{
      title: "T", body: "B", status: "draft", user_id: 999,
      comments_attributes: [
        {{ body: "hi", "_destroy" => "0" }},
        {{ "id" => "1", body: "edited", commentable_id: 42, commentable_type: "Post" }}
      ]
    }}
  )
  permitted = {expr}
  h = permitted.to_h
  over_permitted_top = h.key?("user_id") || h.key?(:user_id)
  comments = h["comments_attributes"] || h[:comments_attributes] || []
  comments = comments.is_a?(Hash) ? comments.values : comments
  over_permitted_nested = comments.any? {{ |c| c.key?("commentable_id") || c.key?(:commentable_id) }}
  has_title = h.key?("title") || h.key?(:title)
  ok = has_title && !over_permitted_top && !over_permitted_nested
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: has_title=#{{has_title}} over_permitted_top(user_id)=#{{over_permitted_top}} over_permitted_nested(commentable_id)=#{{over_permitted_nested}} got=#{{h.inspect}}"
rescue ActionController::UnpermittedParameters => e
  puts "RESULT: FAIL: unpermitted params raised: #{{e.message}}"
rescue => e
  puts "RESULT: FAIL: exception #{{e.class}}: #{{e.message}}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-400:]}"
    detail = {"rc": rc, "out": out, "err": err[-800:], "extracted_expr": expr, "used_permit_bang": permit_over}
    git_reset()
    return rc == 0, behavior, detail

HANDLERS = {"F1": do_f1, "F2": do_f2, "F3": do_f3, "F4": do_f4, "F5": do_f5}

def main():
    all_results = []
    for model in MODELS:
        for pid in ["F1", "F2", "F3", "F4", "F5"]:
            for run in (1, 2, 3):
                content = load_run(pid, model, run)
                code = extract_code(content)
                result = {"prompt": pid, "model": model, "run": run, "code_extracted": code is not None}
                if code is None:
                    result["executes"] = False
                    result["behavior"] = "FAIL: no code block found"
                else:
                    try:
                        executes, behavior, detail = HANDLERS[pid](content if pid in ("F1", "F2", "F4") else code)
                        result["executes"] = executes
                        result["behavior"] = behavior
                        result["detail"] = detail
                    except Exception as e:
                        git_reset()
                        result["executes"] = False
                        result["behavior"] = f"FAIL: harness exception {type(e).__name__}: {e}"
                all_results.append(result)
                print(f"{model} {pid} run{run}: executes={result['executes']} behavior={result.get('behavior')}")
    write_scores("scores_f.json", all_results)
    print("DONE category F")

if __name__ == "__main__":
    main()
