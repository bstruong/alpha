#!/usr/bin/env python3
import json, os, sys, time, urllib.request

RESULTS_DIR = "/home/brian/benchmarks/results/round2"
RAW_DIR = os.path.join(RESULTS_DIR, "raw")
MODELS = [
    "qwen2.5-coder:7b",
    "qwen2.5-coder:14b",
    "deepseek-coder-v2:16b-lite-instruct-q4_K_M",
]
RUNS_PER_PROMPT = 3
SYSTEM_PROMPT = ("You are an expert Ruby/Rails developer. Respond with idiomatic, "
                  "complete code in a fenced code block. Keep prose brief.")

def safe(name):
    return name.replace(":", "_").replace("/", "_")

def call_ollama(model, prompt_text, timeout=300):
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt_text},
        ],
        "stream": False,
    }
    req = urllib.request.Request(
        "http://localhost:11434/api/chat",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = json.loads(resp.read())
    elapsed = time.time() - t0
    return body, elapsed

def main():
    with open(os.path.join(RESULTS_DIR, "prompts.json")) as f:
        prompts = json.load(f)

    log_path = os.path.join(RESULTS_DIR, "generate.log")
    with open(log_path, "a") as log:
        for model in MODELS:
            for pid, pdata in prompts.items():
                outdir = os.path.join(RAW_DIR, pid, safe(model))
                os.makedirs(outdir, exist_ok=True)
                for run in range(1, RUNS_PER_PROMPT + 1):
                    outfile = os.path.join(outdir, f"run{run}.json")
                    if os.path.exists(outfile):
                        log.write(f"SKIP (exists) {model} {pid} run{run}\n")
                        log.flush()
                        continue
                    try:
                        body, elapsed = call_ollama(model, pdata["text"])
                        with open(outfile, "w") as f:
                            json.dump(body, f, indent=2)
                        content = body.get("message", {}).get("content", "")
                        line = (f"OK {model} {pid} run{run} "
                                f"elapsed={elapsed:.1f}s chars={len(content)}\n")
                        log.write(line)
                        log.flush()
                        print(line, end="")
                    except Exception as e:
                        line = f"ERROR {model} {pid} run{run}: {e}\n"
                        log.write(line)
                        log.flush()
                        print(line, end="")
    print("DONE")

if __name__ == "__main__":
    main()
