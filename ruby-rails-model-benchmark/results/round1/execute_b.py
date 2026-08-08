#!/usr/bin/env python3
import os, re, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from execute_common import (RESULTS_DIR, SANDBOX, MODELS, extract_code, load_run, sh, git_reset, write_scores)

MIG_COUNTER = [20990101000000]  # far-future base, incremented each use to avoid collisions

def next_version():
    MIG_COUNTER[0] += 1
    return str(MIG_COUNTER[0])

def runner_script(name, body):
    path = os.path.join(RESULTS_DIR, f"tmp_{name}.rb")
    with open(path, "w") as f:
        f.write(body)
    return path

def parse_result(out):
    if "RESULT: PASS" in out:
        return "PASS"
    lines = [l for l in out.splitlines() if l.startswith("RESULT: FAIL")]
    if lines:
        return lines[0]
    return "FAIL: no RESULT line"

def underscore(name):
    # mirrors Rails' ActiveSupport::Inflector#underscore closely enough for our class names
    s1 = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s1).lower()

# ---------- B1: migration adding status to articles ----------
def do_b1(code):
    m = re.search(r"class\s+(\w+)\s*<\s*ActiveRecord::Migration", code)
    if m:
        class_name = m.group(1)
    else:
        class_name = "BenchAddStatus"
        code = f"class {class_name} < ActiveRecord::Migration[7.1]\n{code}\nend"
    ver = next_version()
    mig_path = os.path.join(SANDBOX, "db", "migrate", f"{ver}_{underscore(class_name)}.rb")
    with open(mig_path, "w") as f:
        f.write(code)

    rc, out, err = sh("bin/rails db:migrate", timeout=60)
    detail = {"migrate_rc": rc, "migrate_out": out[-1500:], "migrate_err": err[-1500:]}
    if rc != 0:
        sh("bin/rails db:rollback", timeout=30)
        git_reset()
        return False, f"FAIL: migration errored: {err.strip()[-300:]}", detail

    check = runner_script("b1_check", '''
begin
  col = Article.columns_hash["status"]
  has_col = !col.nil?
  default_ok = col && col.default.to_s == "draft"
  idx = ActiveRecord::Base.connection.index_exists?(:articles, :status)
  if has_col && default_ok && idx
    puts "RESULT: PASS"
  else
    puts "RESULT: FAIL: has_col=#{has_col} default=#{col&.default.inspect} index=#{idx}"
  end
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc2, out2, err2 = sh(f"bin/rails runner {check}", timeout=30)
    behavior = parse_result(out2) if rc2 == 0 else f"FAIL: runner errored: {err2.strip()[-300:]}"
    detail["check_out"] = out2
    detail["check_err"] = err2[-1000:]

    sh("bin/rails db:rollback", timeout=30)
    git_reset()
    return rc == 0, behavior, detail

# ---------- B2: User validations ----------
def do_b2(code):
    if "class User" in code:
        file_content = code
    else:
        file_content = f"class User < ApplicationRecord\n{code}\nend"
    with open(os.path.join(SANDBOX, "app", "models", "user.rb"), "w") as f:
        f.write(file_content)

    check = runner_script("b2_check", '''
begin
  User.delete_all
  u1 = User.new(email: "a@example.com", username: "alice", age: 30)
  v1 = u1.valid?
  u2 = User.new(email: nil, username: "al", age: nil)
  v2 = u2.valid?  # should be invalid: no email, username too short
  User.create!(email: "dup@example.com", username: "bobby", age: 20)
  u3 = User.new(email: "DUP@example.com", username: "carly", age: 25)
  v3 = u3.valid?  # should be invalid: case-insensitive dup email
  u4 = User.new(email: "x@example.com", username: "validname", age: nil)
  v4 = u4.valid?  # age nil should be allowed -> valid

  ok = v1 == true && v2 == false && v3 == false && v4 == true
  if ok
    puts "RESULT: PASS"
  else
    puts "RESULT: FAIL: v1=#{v1} v2=#{v2}(errs=#{u2.errors.full_messages}) v3=#{v3}(errs=#{u3.errors.full_messages}) v4=#{v4}(errs=#{u4.errors.full_messages})"
  end
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-300:]}"
    detail = {"runner_rc": rc, "out": out, "err": err[-1000:]}
    git_reset()
    return rc == 0, behavior, detail

# ---------- B3: PostsController#publish ----------
def do_b3(code):
    if "class PostsController" in code:
        controller = code
    else:
        controller = f'''class PostsController < ApplicationController
  before_action :set_post, only: [:publish]

{code}

  private

  def set_post
    @post = Post.find(params[:id])
  end
end
'''
    with open(os.path.join(SANDBOX, "app", "controllers", "posts_controller.rb"), "w") as f:
        f.write(controller)

    routes_path = os.path.join(SANDBOX, "config", "routes.rb")
    with open(routes_path) as f:
        routes = f.read()
    new_routes = routes.replace(
        "Rails.application.routes.draw do",
        "Rails.application.routes.draw do\n  resources :posts, only: [:show] do\n    member { match :publish, via: [:get, :post, :patch, :put] }\n  end"
    )
    with open(routes_path, "w") as f:
        f.write(new_routes)

    test_path = os.path.join(SANDBOX, "test", "integration", "bench_publish_test.rb")
    with open(test_path, "w") as f:
        f.write('''require "test_helper"
class BenchPublishTest < ActionDispatch::IntegrationTest
  test "publish transitions status and sets published_at" do
    post_record = Post.create!(title: "T", status: "draft")
    [:patch, :post, :get, :put].each do |verb|
      begin
        send(verb, "/posts/#{post_record.id}/publish")
        break if response.status < 500
      rescue
        next
      end
    end
    post_record.reload
    ok = post_record.status == "published" && !post_record.published_at.nil? && !response.nil? && response.redirect?
    if ok
      puts "RESULT: PASS"
    else
      puts "RESULT: FAIL: status=#{post_record.status} published_at=#{post_record.published_at.inspect} response=#{response&.status} flash=#{flash.to_h}"
    end
  end
end
''')
    rc, out, err = sh("bin/rails test test/integration/bench_publish_test.rb", timeout=60)
    behavior = parse_result(out) if "RESULT:" in out else f"FAIL: test errored rc={rc}: {err.strip()[-400:]}"
    detail = {"test_rc": rc, "out": out[-2000:], "err": err[-1500:]}
    git_reset()
    return "RESULT: PASS" in out, behavior, detail

# ---------- B4: Order enum + scope ----------
def do_b4(code):
    if "class Order" in code:
        file_content = code
    else:
        file_content = f"class Order < ApplicationRecord\n{code}\nend"
    with open(os.path.join(SANDBOX, "app", "models", "order.rb"), "w") as f:
        f.write(file_content)

    check = runner_script("b4_check", '''
begin
  Order.delete_all
  o = Order.create!(status: "paid")
  enum_ok = o.respond_to?(:paid?) && o.paid?
  invalid_raised = false
  begin
    Order.new(status: "bogus_status")
  rescue ArgumentError
    invalid_raised = true
  end
  recent = Order.create!(status: "pending", created_at: 1.day.ago)
  old = Order.create!(status: "pending", created_at: 30.days.ago)
  scope_ok = Order.respond_to?(:recent) && Order.recent.include?(recent) && !Order.recent.include?(old)
  ok = enum_ok && invalid_raised && scope_ok
  if ok
    puts "RESULT: PASS"
  else
    puts "RESULT: FAIL: enum_ok=#{enum_ok} invalid_raised(validate:true)=#{invalid_raised} scope_ok=#{scope_ok}"
  end
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
''')
    rc, out, err = sh(f"bin/rails runner {check}", timeout=30)
    behavior = parse_result(out) if rc == 0 else f"FAIL: runner errored: {err.strip()[-300:]}"
    detail = {"runner_rc": rc, "out": out, "err": err[-1000:]}
    git_reset()
    return rc == 0, behavior, detail

# ---------- B5: routes.rb admin/articles ----------
def do_b5(code):
    routes_path = os.path.join(SANDBOX, "config", "routes.rb")
    if "Rails.application.routes.draw" in code:
        content = code
    else:
        content = f"Rails.application.routes.draw do\n{code}\nend\n"
    with open(routes_path, "w") as f:
        f.write(content)

    rc, out, err = sh("bin/rails routes 2>&1", timeout=30)
    combined = out + err
    has_publish = bool(re.search(r"admin/articles/:id/publish|admin_.*publish", combined))
    has_archived = bool(re.search(r"admin/articles/archived|archived_admin", combined))
    if rc != 0:
        behavior = f"FAIL: routes.rb errored: {combined.strip()[-400:]}"
    elif has_publish and has_archived:
        behavior = "PASS"
    else:
        behavior = f"FAIL: has_publish={has_publish} has_archived={has_archived}"
    detail = {"routes_rc": rc, "out": combined[-2000:]}
    git_reset()
    return rc == 0, behavior, detail

HANDLERS = {"B1": do_b1, "B2": do_b2, "B3": do_b3, "B4": do_b4, "B5": do_b5}

def main():
    all_results = []
    for model in MODELS:
        for pid in ["B1", "B2", "B3", "B4", "B5"]:
            for run in (1, 2, 3):
                content = load_run(pid, model, run)
                code = extract_code(content)
                result = {"prompt": pid, "model": model, "run": run,
                          "code_extracted": code is not None}
                if code is None:
                    result["executes"] = False
                    result["behavior"] = "FAIL: no code block found in output"
                else:
                    try:
                        executes, behavior, detail = HANDLERS[pid](code)
                        result["executes"] = executes
                        result["behavior"] = behavior
                        result["detail"] = detail
                    except Exception as e:
                        git_reset()
                        result["executes"] = False
                        result["behavior"] = f"FAIL: harness exception {type(e).__name__}: {e}"
                all_results.append(result)
                print(f"{model} {pid} run{run}: executes={result['executes']} behavior={result.get('behavior')}")
    write_scores("scores_b.json", all_results)
    print("DONE category B")

if __name__ == "__main__":
    main()
