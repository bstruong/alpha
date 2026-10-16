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
        with self._lock:
            now = time.monotonic()
            
            # Only add tokens if the current time is greater than or equal to last refill time
            if now >= self._last_refill:
                elapsed = now - self._last_refill
                new_tokens = elapsed * self.refill_rate
                self.tokens = min(self.max_tokens, self.tokens + new_tokens)
                self._last_refill = now
            
            # Check if we have enough tokens
            if self.tokens >= cost:
                self.tokens -= cost
                return True
            else:
                return False