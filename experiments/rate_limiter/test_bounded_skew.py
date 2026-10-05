import time
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
