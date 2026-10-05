import urllib.request
import json
import time
import os
import sys
import re
import subprocess

PROMPT = """Implement the internal logic for the `allow` method in the `TokenBucket` class to make the provided `pytest` pass. Output only the completed Python code block. Do not architect a fallback or write additional tests.

```python
import time
from threading import Lock

class TokenBucket:
    def __init__(self, max_tokens: float, refill_rate: float):
        self.max_tokens = max_tokens
        self.refill_rate = refill_rate
        self.tokens = max_tokens
        self._last_refill = time.monotonic()
        self._lock = Lock()

    def allow(self, cost: float) -> bool:
        # IMPLEMENT
```

Test to satisfy:
```python
def test_clock_skew_preserves_baseline(monkeypatch):
    bucket = TokenBucket(max_tokens=10.0, refill_rate=1.0)
    bucket.tokens = 5.0
    bucket._last_refill = 150.0

    monkeypatch.setattr(time, "monotonic", lambda: 100.0)

    assert bucket.allow(1.0) is True
    assert bucket.tokens == 4.0
    assert bucket._last_refill == 150.0
```"""

def main():
    payload = {
        "model": "./models/qwen3.6-35b-a3b-q4_k_m.gguf",
        "messages": [
            {"role": "user", "content": PROMPT}
        ],
        "temperature": 0.2,
        "max_tokens": 2048,
        "stream": True,
        "chat_template_kwargs": {"enable_thinking": False}
    }

    req = urllib.request.Request(
        "http://localhost:8080/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    print("[STREAMING BENCHMARK] Dispatching payload to http://localhost:8080/v1/chat/completions...", flush=True)
    t0 = time.perf_counter()
    first_token_time = None
    total_chunks = 0

    accumulated_content = []
    accumulated_reasoning = []
    final_timings = None

    with urllib.request.urlopen(req) as resp:
        for raw_line in resp:
            line = raw_line.decode("utf-8").strip()
            if not line.startswith("data: "):
                continue
            data_str = line[6:].strip()
            if data_str == "[DONE]":
                break
            try:
                chunk = json.loads(data_str)
            except Exception:
                continue

            choices = chunk.get("choices", [])
            if choices:
                delta = choices[0].get("delta", {})
                content = delta.get("content", "")
                reasoning = delta.get("reasoning_content", "")

                if (content or reasoning) and first_token_time is None:
                    first_token_time = time.perf_counter()

                if content:
                    accumulated_content.append(content)
                    sys.stdout.write(content)
                    sys.stdout.flush()
                if reasoning:
                    accumulated_reasoning.append(reasoning)

            total_chunks += 1
            if "timings" in chunk:
                final_timings = chunk["timings"]

    t_end = time.perf_counter()
    total_elapsed = t_end - t0
    ttft = (first_token_time - t0) if first_token_time else 0.0

    full_content = "".join(accumulated_content)
    full_reasoning = "".join(accumulated_reasoning)

    output_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Save raw outputs
    with open(os.path.join(output_dir, "bounded_output.txt"), "w", encoding="utf-8") as f:
        f.write(full_content)
    with open(os.path.join(output_dir, "bounded_reasoning.txt"), "w", encoding="utf-8") as f:
        f.write(full_reasoning)

    # Extract python code
    code_match = re.search(r"```python\s*(.*?)\s*```", full_content, re.DOTALL)
    if code_match:
        extracted_code = code_match.group(1)
    else:
        extracted_code = full_content

    # Write generated TokenBucket implementation
    token_bucket_path = os.path.join(output_dir, "generated_token_bucket.py")
    with open(token_bucket_path, "w", encoding="utf-8") as f:
        f.write(extracted_code)

    # Write pytest test suite
    test_code = f'''import time
import pytest
from generated_token_bucket import TokenBucket

def test_clock_skew_preserves_baseline(monkeypatch):
    bucket = TokenBucket(max_tokens=10.0, refill_rate=1.0)
    bucket.tokens = 5.0
    bucket._last_refill = 150.0

    monkeypatch.setattr(time, "monotonic", lambda: 100.0)

    assert bucket.allow(1.0) is True
    assert bucket.tokens == 4.0
    assert bucket._last_refill == 150.0
'''
    test_file_path = os.path.join(output_dir, "test_bounded_skew.py")
    with open(test_file_path, "w", encoding="utf-8") as f:
        f.write(test_code)

    # Execute pytest
    print("\n\n[PYTEST EXECUTION] Running pytest on generated implementation...", flush=True)
    test_res = subprocess.run(
        [sys.executable, "-m", "pytest", test_file_path, "-v"],
        capture_output=True,
        text=True,
        cwd=output_dir
    )
    print(test_res.stdout, flush=True)
    if test_res.stderr:
        print(test_res.stderr, flush=True)

    test_passed = (test_res.returncode == 0)

    results = {
        "wall_time_total_s": total_elapsed,
        "ttft_s": ttft,
        "content_length_chars": len(full_content),
        "reasoning_length_chars": len(full_reasoning),
        "total_chunks": total_chunks,
        "timings": final_timings,
        "pytest_exit_code": test_res.returncode,
        "pytest_passed": test_passed,
        "pytest_output": test_res.stdout
    }

    with open(os.path.join(output_dir, "bounded_metrics.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    print("\n[BENCHMARK SCORECARD SUMMARY]")
    print(f"Test Status: {'PASSED [OK]' if test_passed else 'FAILED [X]'}")
    print(f"Total Wall Time: {total_elapsed:.3f} s")
    print(f"Time To First Token (TTFT): {ttft:.3f} s ({ttft*1000:.1f} ms)")
    if final_timings:
        print(f"Prompt Tokens: {final_timings.get('prompt_n')}")
        print(f"Prompt Eval Time: {final_timings.get('prompt_ms'):.1f} ms")
        print(f"Prefill Throughput: {final_timings.get('prompt_per_second'):.2f} tokens/s")
        print(f"Predicted Tokens: {final_timings.get('predicted_n')}")
        print(f"Predicted Eval Time: {final_timings.get('predicted_ms'):.1f} ms")
        print(f"Decode / Generation Speed: {final_timings.get('predicted_per_second'):.2f} tokens/s")

if __name__ == "__main__":
    main()
