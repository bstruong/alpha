import json, os, re, subprocess, time

RESULTS_DIR = "/home/user/benchmarks/results"
RAW_DIR = os.path.join(RESULTS_DIR, "raw")
SANDBOX = "/home/user/benchmarks/rails-scratch"
MODELS = [
    "qwen2.5-coder:7b",
    "qwen2.5-coder:14b",
    "deepseek-coder-v2:16b-lite-instruct-q4_K_M",
]

def safe(name):
    return name.replace(":", "_").replace("/", "_")

CODE_BLOCK_RE = re.compile(r"```(?:ruby|rb)?\n(.*?)```", re.DOTALL)

def extract_code(content):
    blocks = CODE_BLOCK_RE.findall(content)
    if not blocks:
        return None
    # take the longest block (most likely the real snippet vs a tiny inline example)
    return max(blocks, key=len).strip()

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
