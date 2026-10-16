#!/usr/bin/env python3
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from execute_common import (RESULTS_DIR, SANDBOX, MODELS, extract_code, extract_all_code, load_run, sh,
                             git_reset, write_scores, runner_script, parse_result)

# Gem-tutorial-style responses often contain several separate code blocks
# (model change, usage example, view snippet) — picking the *longest* block
# (extract_code's default) can grab a usage example instead of the actual
# model/controller definition. Prefer the block containing a marker specific
# to what we're actually going to merge into a file.
MARKERS = {
    "E1": ["def index", "ArticlesController"],
    "E2": ["has_one_attached", "has_many_attached"],
    "E3": ["ransack", "class Article"],
}

TARGET_CLASS = {"E1": "ArticlesController", "E2": "Article", "E3": "Article"}

def extract_targeted(content, pid):
    blocks = extract_all_code(content)
    if not blocks:
        return None
    chosen = None
    for marker in MARKERS.get(pid, []):
        for b in blocks:
            if marker in b:
                chosen = b
                break
        if chosen:
            break
    if chosen is None:
        chosen = max(blocks, key=len)
    # A single fence can contain multiple files concatenated (model, migration,
    # view, controller, routes...) separated only by "# path/to/file" comments.
    # If a stricter class-scoped match exists inside the chosen block, prefer
    # it over the raw (possibly multi-file) block.
    klass = TARGET_CLASS.get(pid)
    if klass:
        m = re.search(rf"class\s+{klass}\b.*?\nend\b", chosen, re.DOTALL)
        if m:
            return m.group(0)
    return chosen

KNOWN_KAMINARI_METHODS = {"page", "per", "total_pages", "current_page", "num_pages", "padding", "total_count"}
KNOWN_ACTIVESTORAGE_METHODS = {"has_one_attached", "has_many_attached", "attach", "attached?", "purge", "variant", "url", "attachment"}
KNOWN_RANSACK_METHODS = {"ransack", "ransackable_attributes", "result", "ransackable_associations"}

def detect_hallucination(code, known_methods, gem_hint):
    # crude heuristic: look for `.method_name(` calls that look gem-related but aren't in the known set
    # only flag ones that appear alongside gem-specific context words, to avoid false positives on generic Ruby
    calls = set(re.findall(r"\.(\w+)\s*[\(\{]", code))
    return calls

# ---------- E1: Kaminari pagination on ArticlesController#index ----------
def do_e1(code):
    if "class ArticlesController" in code:
        controller = code
    else:
        controller = f'''class ArticlesController < ApplicationController
{code}
end
'''
    with open(os.path.join(SANDBOX, "app", "controllers", "articles_controller.rb"), "w") as f:
        f.write(controller)
    os.makedirs(os.path.join(SANDBOX, "app", "views", "articles"), exist_ok=True)
    with open(os.path.join(SANDBOX, "app", "views", "articles", "index.html.erb"), "w") as f:
        f.write('<%= @articles.map { |a| "TITLEMARKER:#{a.title}:ENDMARKER" }.join(" ") %>\n')

    test_path = os.path.join(SANDBOX, "test", "integration", "bench_e1_test.rb")
    with open(test_path, "w") as f:
        f.write('''require "test_helper"
class BenchE1Test < ActionDispatch::IntegrationTest
  test "articles index paginates" do
    Article.delete_all
    15.times { |i| Article.create!(title: "Article #{i}", body: "body") }
    total_in_db = Article.count
    get "/articles"
    if response.status >= 500
      puts "RESULT: FAIL: server error #{response.status}: #{response.body[0..500]}"
    else
      titles_shown = response.body.scan("TITLEMARKER:").length
      ok = titles_shown <= 10 && titles_shown > 0 && titles_shown < total_in_db
      puts ok ? "RESULT: PASS" : "RESULT: FAIL: shown=#{titles_shown} total_in_db=#{total_in_db} (expected <=10 and < total_in_db) body=#{response.body[0..300]}"
    end
  end
end
''')
    rc, out, err = sh("bin/rails test test/integration/bench_e1_test.rb", timeout=60)
    hallucinated = None
    combined = out + err
    if "NoMethodError" in combined:
        m = re.search(r"undefined method [`']([\w?!=]+)[`']", combined)
        if m:
            hallucinated = m.group(1)
    behavior = parse_result(out) if "RESULT:" in out else f"FAIL: test errored rc={rc}: {err.strip()[-400:]}"
    detail = {"rc": rc, "out": out[-1500:], "err": err[-1000:]}
    git_reset()
    return "RESULT: PASS" in out, behavior, detail, hallucinated

# ---------- E2: ActiveStorage has_one_attached :cover_image ----------
def do_e2(code):
    if "class Article" in code:
        file_content = code
    else:
        file_content = f"class Article < ApplicationRecord\n{code}\nend"
    with open(os.path.join(SANDBOX, "app", "models", "article.rb"), "w") as f:
        f.write(file_content)

    check = runner_script("e2_check", '''
begin
  a = Article.create!(title: "T", body: "B")
  responds = a.respond_to?(:cover_image)
  a.cover_image.attach(io: StringIO.new("hello"), filename: "test.txt", content_type: "text/plain")
  attached = a.cover_image.attached?
  ok = responds && attached
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: responds=#{responds} attached=#{attached}"
rescue NoMethodError => e
  puts "RESULT: FAIL: hallucinated method: #{e.message}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    hallucinated = None
    if "hallucinated method" in out:
        m = re.search(r"undefined method [`']([\w?!=]+)[`']", out)
        if m:
            hallucinated = m.group(1)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-300:]}"
    detail = {"rc": rc, "out": out, "err": err[-800:]}
    git_reset()
    return rc == 0, behavior, detail, hallucinated

# ---------- E3: ransack fuzzy search scope on Article ----------
def do_e3(code):
    if "class Article" in code:
        file_content = code
    else:
        file_content = f"class Article < ApplicationRecord\n{code}\nend"
    with open(os.path.join(SANDBOX, "app", "models", "article.rb"), "w") as f:
        f.write(file_content)

    check = runner_script("e3_check", '''
begin
  Article.create!(title: "Ruby on Rails Guide", body: "learn rails")
  Article.create!(title: "Something else", body: "unrelated")
  result = Article.ransack(title_or_body_cont: "rails").result
  ok = result.is_a?(ActiveRecord::Relation) && result.count >= 1
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: result_class=#{result.class} count=#{result.count rescue "n/a"}"
rescue NoMethodError => e
  puts "RESULT: FAIL: hallucinated method: #{e.message}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    hallucinated = None
    if "hallucinated method" in out:
        m = re.search(r"undefined method [`']([\w?!=]+)[`']", out)
        if m:
            hallucinated = m.group(1)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-300:]}"
    detail = {"rc": rc, "out": out, "err": err[-800:]}
    git_reset()
    return rc == 0, behavior, detail, hallucinated

HANDLERS = {"E1": do_e1, "E2": do_e2, "E3": do_e3}

def main():
    all_results = []
    for model in MODELS:
        for pid in ["E1", "E2", "E3"]:
            for run in (1, 2, 3):
                content = load_run(pid, model, run)
                code = extract_targeted(content, pid)
                result = {"prompt": pid, "model": model, "run": run, "code_extracted": code is not None}
                if code is None:
                    result["executes"] = False
                    result["behavior"] = "FAIL: no code block found"
                    result["hallucinated_api"] = None
                else:
                    try:
                        executes, behavior, detail, hallucinated = HANDLERS[pid](code)
                        result["executes"] = executes
                        result["behavior"] = behavior
                        result["detail"] = detail
                        result["hallucinated_api"] = hallucinated
                    except Exception as e:
                        git_reset()
                        result["executes"] = False
                        result["behavior"] = f"FAIL: harness exception {type(e).__name__}: {e}"
                        result["hallucinated_api"] = None
                all_results.append(result)
                print(f"{model} {pid} run{run}: executes={result['executes']} behavior={result.get('behavior')} hallucinated={result.get('hallucinated_api')}")
    write_scores("scores_e.json", all_results)
    print("DONE category E")

if __name__ == "__main__":
    main()
