import json, os, re, subprocess, time

RESULTS_DIR = "/home/user/benchmarks/results/round3"
RAW_DIR = os.path.join(RESULTS_DIR, "raw")
SANDBOX = "/home/user/benchmarks/rails-scratch"
MODELS = [
    "qwen3:8b",
]

def safe(name):
    return name.replace(":", "_").replace("/", "_")

def extract_all_code_with_lang(content):
    """Line-based fence parser. A regex that treats a bare ``` as both a
    valid open and close marker mis-pairs a closing fence with the next
    opening fence when non-ruby-tagged blocks (```bash, ```erb, bare ```)
    are interspersed, silently capturing prose as fake "code". Toggling a
    boolean per fence line avoids that ambiguity entirely."""
    blocks = []
    in_block = False
    lang = None
    current = []
    for line in content.split("\n"):
        stripped = line.strip()
        if not in_block and stripped.startswith("```"):
            in_block = True
            lang = stripped[3:].strip()
            current = []
        elif in_block and stripped == "```":
            in_block = False
            blocks.append((lang, "\n".join(current).strip()))
        elif in_block:
            current.append(line)
    return blocks

def extract_all_code(content):
    return [b for _, b in extract_all_code_with_lang(content) if b]

def extract_code(content):
    """Prefer ruby/rb-tagged or bare-tagged blocks over bash/erb/etc.; among
    those, take the longest (most likely the real snippet vs a tiny inline
    example)."""
    tagged = extract_all_code_with_lang(content)
    if not tagged:
        return None
    preferred = [b for lang, b in tagged if lang in ("ruby", "rb", "") and b]
    pool = preferred if preferred else [b for _, b in tagged if b]
    if not pool:
        return None
    return max(pool, key=len).strip()

def load_run(prompt_id, model, run):
    path = os.path.join(RAW_DIR, prompt_id, safe(model), f"run{run}.json")
    with open(path) as f:
        body = json.load(f)
    return body.get("message", {}).get("content", "")

def sh(cmd, cwd=SANDBOX, timeout=60):
    try:
        p = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True,
                            text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired as e:
        return -1, e.stdout or "", f"TIMEOUT after {timeout}s"

def git_reset():
    sh("git checkout -- . && git clean -fd", cwd=SANDBOX, timeout=30)

def write_scores(name, data):
    with open(os.path.join(RESULTS_DIR, name), "w") as f:
        json.dump(data, f, indent=2)

def parse_result(out):
    if "RESULT: PASS" in out:
        return "PASS"
    lines = [l for l in out.splitlines() if l.startswith("RESULT: FAIL")]
    if lines:
        return lines[0]
    return "FAIL: no RESULT line"

def runner_script(name, body):
    path = os.path.join(RESULTS_DIR, f"tmp_{name}.rb")
    with open(path, "w") as f:
        f.write(body)
    return path
