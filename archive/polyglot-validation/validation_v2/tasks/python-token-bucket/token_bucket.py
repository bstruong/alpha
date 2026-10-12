"""Token bucket rate limiter with built-in assertions."""

import time


class TokenBucket:
    """A token bucket rate limiter.

    Tokens are added at a fixed rate up to a maximum capacity.
    Each consume() call deducts the requested number of tokens.
    """

    def __init__(self, capacity: float, refill_rate: float) -> None:
        if capacity <= 0:
            raise ValueError("capacity must be > 0")
        if refill_rate <= 0:
            raise ValueError("refill_rate must be > 0")
        self.capacity = capacity
        self.refill_rate = refill_rate  # tokens per second
        self.tokens = capacity
        self._last_refill = time.monotonic()

    def _refill(self) -> None:
        now = time.monotonic()
        elapsed = now - self._last_refill
        self.tokens = min(self.capacity, self.tokens + elapsed * self.refill_rate)
        self._last_refill = now

    def consume(self, tokens: float = 1.0) -> bool:
        """Try to consume *tokens*. Returns True if successful."""
        if tokens <= 0:
            raise ValueError("tokens must be > 0")
        self._refill()
        if self.tokens >= tokens:
            self.tokens -= tokens
            return True
        return False

    @property
    def available(self) -> float:
        """Current available tokens (after refill)."""
        self._refill()
        return self.tokens


def _assert_eq(actual, expected, msg: str) -> None:
    if actual != expected:
        raise AssertionError(f"{msg}: expected {expected}, got {actual}")


def _assert_almost_eq(actual, expected, msg: str, places: int = 6) -> None:
    if round(actual - expected, places) != 0:
        raise AssertionError(f"{msg}: expected ~{expected}, got {actual}")


# --- Assertions ---

# 1. Initial capacity
bucket = TokenBucket(capacity=10.0, refill_rate=1.0)
_assert_eq(bucket.available, 10.0, "initial capacity")

# 2. Consume exact tokens
assert bucket.consume(10.0), "should consume all 10 tokens"
_assert_almost_eq(bucket.available, 0.0, "after consuming all", places=4)

# 3. Exhausted bucket rejects
assert not bucket.consume(1.0), "should fail when empty"

# 4. Refill over time
time.sleep(0.15)  # refill_rate=1.0 => ~0.15 tokens added
assert bucket.consume(0.1), "should consume after brief wait"

# 5. Capacity cap
bucket2 = TokenBucket(capacity=5.0, refill_rate=100.0)
time.sleep(0.1)  # would add 10 tokens, but capped at 5
_assert_almost_eq(bucket2.available, 5.0, "capped at capacity", places=0)

# 6. Invalid inputs
try:
    TokenBucket(capacity=0, refill_rate=1.0)
    raise AssertionError("should have raised ValueError for capacity=0")
except ValueError:
    pass

try:
    bucket.consume(-1)
    raise AssertionError("should have raised ValueError for negative tokens")
except ValueError:
    pass

print("python-token-bucket: all assertions passed.")
