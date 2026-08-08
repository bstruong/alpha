#!/usr/bin/env python3
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from execute_common import RESULTS_DIR, MODELS, extract_code, load_run, sh, parse_result, write_scores

TMP = os.path.join(RESULTS_DIR, "tmp_h.rb")

def r1_idiom(code):
    if re.search(r"\b(name|age|email):\s*(,|\})", code):
        return "3.1-shorthand"
    if re.search(r"\bname:\s*name\b", code):
        return "pre-3.1-explicit"
    return "unknown"

def r1_driver(code):
    script = code + '''
before_locals = nil
name = "Ada"
age = 30
email = "ada@example.com"
new_methods = Object.private_instance_methods(false)
raise "no method defined" if new_methods.empty?
mname = new_methods.first
result = nil
begin
  result = send(mname, name: name, age: age, email: email)
rescue ArgumentError, NoMethodError
  begin
    result = send(mname, name, age, email)
  rescue => e2
    puts "RESULT: FAIL: could not call method either style: #{e2.class}: #{e2.message}"
    exit
  end
end
norm = {}
(result || {}).each { |k, v| norm[k.to_s] = v }
ok = norm["name"] == name && norm["age"] == age && norm["email"] == email
puts ok ? "RESULT: PASS" : "RESULT: FAIL: got #{norm.inspect}"
'''
    with open(TMP, "w") as f:
        f.write(script)
    rc, out, err = sh(f"ruby {TMP}", cwd=RESULTS_DIR, timeout=10)
    return rc, out, err

def r2_idiom(code):
    if "Data.define" in code:
        return "3.2-Data.define"
    if "Struct.new" in code:
        return "pre-3.2-Struct"
    if re.search(r"\bclass\s+Point\b", code):
        return "pre-3.2-hand-rolled-class"
    return "unknown"

def r2_driver(code):
    script = code + '''
p1 = nil
begin
  p1 = Point.new(x: 1, y: 2)
rescue ArgumentError, NoMethodError
  p1 = Point.new(1, 2)
end
coords_ok = p1.x == 1 && p1.y == 2
immutable_ok = !p1.respond_to?(:x=) || p1.frozen?
ok = coords_ok && immutable_ok
puts ok ? "RESULT: PASS" : "RESULT: FAIL: coords_ok=#{coords_ok} immutable_ok=#{immutable_ok} x=#{p1.x rescue nil} y=#{p1.y rescue nil}"
'''
    with open(TMP, "w") as f:
        f.write(script)
    rc, out, err = sh(f"ruby {TMP}", cwd=RESULTS_DIR, timeout=10)
    return rc, out, err

def r3_idiom(code):
    if "..." in code:
        return "3.2-anonymous-forwarding"
    if re.search(r"\*\w*args?.*\*\*\w*kwargs?", code) or (re.search(r"\*\w+", code) and re.search(r"\*\*\w+", code)):
        return "pre-3.2-explicit-splat"
    if re.search(r"\*\w+", code):
        return "pre-3.2-explicit-splat-args-only"
    return "unknown"

def r3_driver(code):
    script = '''
def target(*args, **kwargs, &block)
  [args, kwargs, block ? block.call : nil]
end
''' + code + '''
before = Object.private_instance_methods(false) - [:target]
new_methods = Object.private_instance_methods(false).select { |m| m != :target && method(m).source_location && method(m).source_location[0] == __FILE__ }
mname = new_methods.first || :wrapper
result = nil
begin
  result = send(mname, 1, 2, foo: "bar") { "blockval" }
rescue => e
  puts "RESULT: FAIL: calling #{mname} raised #{e.class}: #{e.message}"
  exit
end
args, kwargs, blockres = result
ok = args == [1, 2] && kwargs == {foo: "bar"} && blockres == "blockval"
puts ok ? "RESULT: PASS" : "RESULT: FAIL: got args=#{args.inspect} kwargs=#{kwargs.inspect} block=#{blockres.inspect}"
'''
    with open(TMP, "w") as f:
        f.write(script)
    rc, out, err = sh(f"ruby {TMP}", cwd=RESULTS_DIR, timeout=10)
    return rc, out, err

def extract_block_body(code):
    start = code.find("{")
    if start != -1:
        depth = 0
        for i in range(start, len(code)):
            if code[i] == "{":
                depth += 1
            elif code[i] == "}":
                depth -= 1
                if depth == 0:
                    return "brace", code[start + 1:i].strip()
    m = re.search(r"\bdo\b(.*?)\bend\b", code, re.DOTALL)
    if m:
        return "do_end", m.group(1).strip()
    return None, None

def r4_idiom(code):
    style, body = extract_block_body(code)
    if body is None:
        return "unknown", None
    if re.search(r"\bit\b", body):
        return "3.4-trap-it", body
    if re.search(r"_1\b", body):
        return "2.7-numbered-param", body
    if re.search(r"\|\s*\w+\s*\|", body):
        return "explicit-named-param", body
    return "unknown", body

def r4_driver(code):
    style, body = extract_block_body(code)
    if body is None:
        return -1, "", "no block body extracted"
    if style == "brace":
        expr = f"result = [1, 2, 3].map {{ {body} }}\n"
    else:
        expr = f"result = [1, 2, 3].map do {body} end\n"
    script = expr + '''
puts(result == [2, 4, 6] ? "RESULT: PASS" : "RESULT: FAIL: got #{result.inspect}")
'''
    with open(TMP, "w") as f:
        f.write(script)
    rc, out, err = sh(f"ruby {TMP}", cwd=RESULTS_DIR, timeout=10)
    return rc, out, err

HANDLERS = {
    "R1": (r1_driver, r1_idiom),
    "R2": (r2_driver, r2_idiom),
    "R3": (r3_driver, r3_idiom),
}

def main():
    all_results = []
    for model in MODELS:
        for pid in ["R1", "R2", "R3", "R4"]:
            for run in (1, 2, 3):
                content = load_run(pid, model, run)
                code = extract_code(content)
                result = {"prompt": pid, "model": model, "run": run,
                          "code_extracted": code is not None}
                if code is None:
                    result["executes"] = False
                    result["behavior"] = "FAIL: no code block found"
                    result["idiom"] = "unknown"
                    result["it_trap"] = False
                    all_results.append(result)
                    print(f"{model} {pid} run{run}: NO CODE EXTRACTED")
                    continue

                if pid == "R4":
                    idiom, body = r4_idiom(code)
                    rc, out, err = r4_driver(code)
                    result["idiom"] = idiom
                    result["block_body"] = body
                    result["it_trap"] = (idiom == "3.4-trap-it")
                    if rc != 0:
                        result["executes"] = False
                        result["behavior"] = f"FAIL: ruby exited {rc}: {err.strip()[-300:]}"
                    else:
                        result["executes"] = "NameError" not in out
                        result["behavior"] = parse_result(out) if "RESULT:" in out else f"FAIL: no result: {out.strip()[-200:]}"
                        if "NameError" in err or "undefined local variable or method" in err:
                            result["executes"] = False
                            result["behavior"] = f"FAIL: NameError (trap fired): {err.strip()[-300:]}"
                else:
                    driver, idiom_fn = HANDLERS[pid]
                    result["idiom"] = idiom_fn(code)
                    result["it_trap"] = False
                    rc, out, err = driver(code)
                    if rc != 0:
                        result["executes"] = False
                        result["behavior"] = f"FAIL: ruby exited {rc}: {err.strip()[-400:]}"
                    else:
                        result["executes"] = True
                        result["behavior"] = parse_result(out)

                result["stdout"] = out.strip()[-1000:] if 'out' in dir() else ""
                all_results.append(result)
                print(f"{model} {pid} run{run}: executes={result['executes']} behavior={result.get('behavior')} idiom={result.get('idiom')}")
    write_scores("scores_h.json", all_results)
    print("DONE category H")

if __name__ == "__main__":
    main()
