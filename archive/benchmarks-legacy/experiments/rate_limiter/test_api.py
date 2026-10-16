import urllib.request
import json

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

payload = {
    "messages": [
        {"role": "user", "content": PROMPT}
    ],
    "max_tokens": 1024,
    "temperature": 0.2,
    "chat_template_kwargs": {"enable_thinking": False}
}

req = urllib.request.Request(
    "http://localhost:8080/v1/chat/completions",
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"}
)

with urllib.request.urlopen(req) as resp:
    res = json.loads(resp.read().decode("utf-8"))
    content = res["choices"][0]["message"].get("content", "")
    print("Response Content:")
    print(content)
    print("\nTimings:")
    print(json.dumps(res.get("timings"), indent=2))

