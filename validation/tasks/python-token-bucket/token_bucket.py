"""Token bucket rate limiter implementation."""
import time


class TokenBucket:
    def __init__(self, capacity: int, refill_rate: float):
        self.capacity = capacity
        self.tokens = capacity
        self.refill_rate = refill_rate
        self.last_refill = time.monotonic()

    def _refill(self):
        now = time.monotonic()
        elapsed = now - self.last_refill
        self.tokens = min(self.capacity, self.tokens + elapsed * self.refill_rate)
        self.last_refill = now

    def consume(self, n: int = 1) -> bool:
        self._refill()
        if self.tokens >= n:
            self.tokens -= n
            return True
        return False

    @property
    def available(self) -> float:
        self._refill()
        return self.tokens


if __name__ == "__main__":
    bucket = TokenBucket(capacity=5, refill_rate=1.0)
    assert bucket.consume(3), "Should consume 3 tokens"
    assert abs(bucket.available - 2.0) < 0.1, f"Expected ~2.0, got {bucket.available}"
    assert not bucket.consume(5), "Should not consume 5 tokens"
    print("All assertions passed.")
