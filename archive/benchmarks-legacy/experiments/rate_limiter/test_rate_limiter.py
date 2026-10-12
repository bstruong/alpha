"""Comprehensive test suite for TokenBucketLimiter, RedisLimiter, and FallbackRateLimiter."""

from __future__ import annotations

import concurrent.futures
import threading
import unittest.mock
from typing import Any

import fakeredis
import pytest
import redis

from app.core.rate_limiter import (
    FallbackRateLimiter,
    RateLimiterBackendError,
    RedisLimiter,
    TokenBucketLimiter,
)


class MockClock:
    """Deterministic, thread-safe controllable clock for temporal testing."""

    def __init__(self, initial_time: float = 1000.0) -> None:
        self._current_time: float = initial_time
        self._lock = threading.Lock()

    def __call__(self) -> float:
        with self._lock:
            return self._current_time

    def advance(self, seconds: float) -> None:
        with self._lock:
            self._current_time += seconds

    def set(self, timestamp: float) -> None:
        with self._lock:
            self._current_time = timestamp


# ===========================================================================
# 1. Validation & Error Handling
# ===========================================================================


class TestInputValidation:
    """Validate strict contract enforcement on initialization and invocation."""

    @pytest.mark.parametrize(
        ("capacity", "refill_rate"),
        [
            (0.0, 10.0),
            (-5.0, 10.0),
            (10.0, -0.01),
            (10.0, -1.0),
            (float("nan"), 10.0),
            (10.0, float("nan")),
            (float("inf"), 10.0),
            (True, 10.0),  # Booleans are ints in Python, must be rejected
            (10.0, False),
        ],
    )
    def test_token_bucket_invalid_init(self, capacity: Any, refill_rate: Any) -> None:
        with pytest.raises(ValueError):
            TokenBucketLimiter(capacity=capacity, refill_rate=refill_rate)

    @pytest.mark.parametrize("max_keys", [0, -10, False, True])
    def test_token_bucket_invalid_max_keys(self, max_keys: Any) -> None:
        with pytest.raises(ValueError):
            TokenBucketLimiter(capacity=10.0, refill_rate=1.0, max_keys=max_keys)

    @pytest.mark.parametrize(
        "cost", [0.0, -1.0, -0.001, float("nan"), float("inf"), True, False]
    )
    def test_allow_rejects_invalid_cost(self, cost: Any) -> None:
        limiter = TokenBucketLimiter(capacity=10.0, refill_rate=1.0)
        with pytest.raises(
            ValueError, match="Cost must be a strictly positive finite number"
        ):
            limiter.allow("user:123", cost=cost)

    @pytest.mark.parametrize("key", ["", 123, None, [], {}])
    def test_allow_rejects_invalid_key(self, key: Any) -> None:
        limiter = TokenBucketLimiter(capacity=10.0, refill_rate=1.0)
        with pytest.raises(ValueError, match="Key must be a non-empty string"):
            limiter.allow(key, cost=1.0)

    @pytest.mark.parametrize("key", ["", 123, None])
    def test_reset_rejects_invalid_key(self, key: Any) -> None:
        limiter = TokenBucketLimiter(capacity=10.0, refill_rate=1.0)
        with pytest.raises(ValueError, match="Key must be a non-empty string"):
            limiter.reset(key)


# ===========================================================================
# 2. Burst Capacity & Refill Dynamics
# ===========================================================================


class TestBurstAndRefill:
    """Verify exact burst limits and deterministic temporal refill dynamics."""

    def test_burst_capacity_exhaustion(self) -> None:
        clock = MockClock(100.0)
        limiter = TokenBucketLimiter(capacity=5.0, refill_rate=0.0, clock=clock)

        # First 5 calls of cost 1 must succeed
        for _ in range(5):
            assert limiter.allow("client:1", cost=1.0) is True

        # 6th call must fail due to exhausted burst capacity
        assert limiter.allow("client:1", cost=1.0) is False
        assert limiter.get_tokens("client:1") == 0.0

    def test_variable_cost_consumption(self) -> None:
        clock = MockClock(100.0)
        limiter = TokenBucketLimiter(capacity=10.0, refill_rate=0.0, clock=clock)

        assert limiter.allow("client:1", cost=3.5) is True
        assert limiter.get_tokens("client:1") == 6.5

        assert limiter.allow("client:1", cost=6.5) is True
        assert limiter.get_tokens("client:1") == 0.0

        # Excess cost rejected
        assert limiter.allow("client:1", cost=0.1) is False

    def test_temporal_refill_cadence(self) -> None:
        clock = MockClock(100.0)
        # 10 tokens capacity, 2 tokens/second refill
        limiter = TokenBucketLimiter(capacity=10.0, refill_rate=2.0, clock=clock)

        # Exhaust all 10 tokens
        assert limiter.allow("client:1", cost=10.0) is True
        assert limiter.allow("client:1", cost=1.0) is False

        # Advance by 1.5 seconds -> 3.0 tokens refilled
        clock.advance(1.5)
        assert limiter.get_tokens("client:1") == pytest.approx(3.0)

        # Consume 2.0 tokens -> 1.0 remains
        assert limiter.allow("client:1", cost=2.0) is True
        assert limiter.get_tokens("client:1") == pytest.approx(1.0)

        # Advance by 10.0 seconds -> should cap at max capacity (10.0), not overflow
        clock.advance(10.0)
        assert limiter.get_tokens("client:1") == 10.0
        assert limiter.allow("client:1", cost=10.0) is True
        assert limiter.allow("client:1", cost=0.001) is False


# ===========================================================================
# 3. Clock Skew Mitigation
# ===========================================================================


class TestClockSkewResilience:
    """Verify that system time jumping backwards does not corrupt token balances."""

    def test_clock_jump_backwards_does_not_drain_or_burst(self) -> None:
        clock = MockClock(100.0)
        limiter = TokenBucketLimiter(capacity=10.0, refill_rate=2.0, clock=clock)

        # Initial call at T=100 consumes 4 tokens -> 6 tokens remain
        assert limiter.allow("client:1", cost=4.0) is True
        assert limiter.get_tokens("client:1") == 6.0

        # Clock jumps BACKWARDS from T=100 to T=80 (NTP correction or leap second)
        clock.set(80.0)

        # Call at T=80: elapsed is -20.0s.
        # Should detect clock skew, clamp elapsed to 0, preserve 6.0 tokens, and NOT move baseline to T=80!
        assert limiter.allow("client:1", cost=3.0) is True
        # 3.0 tokens remaining
        assert limiter.get_tokens("client:1") == 3.0

        # Call at T=90: still before original baseline T=100. Should still clamp and not refill.
        clock.set(90.0)
        assert limiter.allow("client:1", cost=3.0) is True
        assert limiter.get_tokens("client:1") == 0.0

        # Clock advances past original baseline to T=102.
        # Elapsed since T=100 should be 2.0s, yielding 4.0 tokens (NOT 22.0s / 44 tokens).
        clock.set(102.0)
        assert limiter.get_tokens("client:1") == pytest.approx(4.0)
        assert limiter.allow("client:1", cost=4.0) is True
        assert limiter.allow("client:1", cost=0.1) is False


# ===========================================================================
# 4. Concurrency & Striped Locking
# ===========================================================================


class TestParallelConcurrency:
    """Verify thread safety, exact worker boundary assertions, and striped locking."""

    def test_concurrent_competition_on_single_key(self) -> None:
        """50 worker threads competing for a single bucket with exact boundary assertion."""
        # 40 total tokens available, 0 refill rate
        limiter = TokenBucketLimiter(capacity=40.0, refill_rate=0.0)
        num_workers = 50
        requests_per_worker = 2  # Total requests = 100

        allowed_count = 0
        denied_count = 0
        count_lock = threading.Lock()

        def worker_task() -> None:
            nonlocal allowed_count, denied_count
            for _ in range(requests_per_worker):
                ok = limiter.allow("shared_target", cost=1.0)
                with count_lock:
                    if ok:
                        allowed_count += 1
                    else:
                        denied_count += 1

        with concurrent.futures.ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker_task) for _ in range(num_workers)]
            concurrent.futures.wait(futures)

        # Exact boundary assertion: exactly 40 allowed, exactly 60 denied
        assert allowed_count == 40
        assert denied_count == 60
        assert allowed_count + denied_count == num_workers * requests_per_worker

    def test_concurrent_independent_keys_no_contention(self) -> None:
        """Concurrent workers targeting distinct keys demonstrate striped / per-bucket isolation."""
        num_keys = 20
        tokens_per_key = 10.0
        limiter = TokenBucketLimiter(capacity=tokens_per_key, refill_rate=0.0)

        allowed_per_key: dict[str, int] = {f"user:{i}": 0 for i in range(num_keys)}
        dict_lock = threading.Lock()

        def worker_for_key(key: str) -> None:
            for _ in range(int(tokens_per_key)):
                if limiter.allow(key, cost=1.0):
                    with dict_lock:
                        allowed_per_key[key] += 1

        with concurrent.futures.ThreadPoolExecutor(max_workers=num_keys) as executor:
            futures = [
                executor.submit(worker_for_key, f"user:{i}") for i in range(num_keys)
            ]
            concurrent.futures.wait(futures)

        # Every independent key must have had all 10 tokens consumed without interference
        for key, count in allowed_per_key.items():
            assert count == 10, f"Key {key} failed to consume all tokens"


# ===========================================================================
# 5. State Reset & High-Cardinality Memory Bounds
# ===========================================================================


class TestStateManagementAndMemoryBounds:
    """Verify reset capability and bounded memory under high key cardinality."""

    def test_reset_restores_capacity(self) -> None:
        limiter = TokenBucketLimiter(capacity=5.0, refill_rate=0.0)
        assert limiter.allow("key:reset", cost=5.0) is True
        assert limiter.allow("key:reset", cost=1.0) is False

        limiter.reset("key:reset")
        assert limiter.get_tokens("key:reset") == 5.0
        assert limiter.allow("key:reset", cost=5.0) is True

    def test_lru_and_stale_eviction_prevents_memory_leak(self) -> None:
        clock = MockClock(100.0)
        max_keys = 25
        limiter = TokenBucketLimiter(
            capacity=10.0,
            refill_rate=1.0,
            max_keys=max_keys,
            stale_ttl=10.0,
            clock=clock,
        )

        # Insert 50 unique keys (twice max_keys)
        for i in range(50):
            assert limiter.allow(f"session:{i}", cost=1.0) is True

        # Total tracked buckets must never exceed max_keys
        assert len(limiter) <= max_keys

        # Advance time by 20s (all surviving buckets become full and idle > stale_ttl)
        clock.advance(20.0)
        pruned = limiter.cleanup()
        assert pruned > 0
        assert len(limiter) == 0


# ===========================================================================
# 6. RedisLimiter & Atomic Lua Script (Hermetic via FakeRedis)
# ===========================================================================


class TestRedisLimiter:
    """Hermetic validation of RedisLimiter and the atomic Lua token bucket script."""

    @pytest.fixture
    def redis_client(self) -> fakeredis.FakeRedis:
        client = fakeredis.FakeRedis()
        client.flushall()
        return client

    def test_redis_limiter_burst_and_refill(
        self, redis_client: fakeredis.FakeRedis
    ) -> None:
        limiter = RedisLimiter(
            client=redis_client, capacity=5.0, refill_rate=5.0, key_ttl=10
        )

        # Burst exhaustion
        for _ in range(5):
            assert limiter.allow("tenant:1", cost=1.0) is True

        assert limiter.allow("tenant:1", cost=1.0) is False

        # Reset
        limiter.reset("tenant:1")
        assert limiter.allow("tenant:1", cost=5.0) is True
        assert limiter.allow("tenant:1", cost=1.0) is False

    def test_redis_limiter_validation(self, redis_client: fakeredis.FakeRedis) -> None:
        with pytest.raises(ValueError):
            RedisLimiter(client=redis_client, capacity=-1.0, refill_rate=1.0)

        with pytest.raises(ValueError):
            RedisLimiter(client=redis_client, capacity=10.0, refill_rate=-1.0)

        limiter = RedisLimiter(client=redis_client, capacity=10.0, refill_rate=1.0)
        with pytest.raises(ValueError):
            limiter.allow("", cost=1.0)

        with pytest.raises(ValueError):
            limiter.allow("user:1", cost=-1.0)

    def test_redis_limiter_backend_error_handling(self) -> None:
        """Verify RedisLimiter wraps backend network/server failures cleanly."""
        mock_client = unittest.mock.MagicMock(spec=redis.Redis)
        mock_script = unittest.mock.MagicMock(
            side_effect=redis.ConnectionError("Connection refused")
        )
        mock_client.register_script.return_value = mock_script

        limiter = RedisLimiter(client=mock_client, capacity=10.0, refill_rate=1.0)
        with pytest.raises(RateLimiterBackendError, match="Connection refused"):
            limiter.allow("key:fail", cost=1.0)


# ===========================================================================
# 7. FallbackRateLimiter (Tiered Distributed / Local)
# ===========================================================================


class TestFallbackRateLimiter:
    """Verify automatic failover from degraded primary (Redis) to local in-memory fallback."""

    def test_fallback_activated_on_backend_failure(self) -> None:
        mock_client = unittest.mock.MagicMock(spec=redis.Redis)
        mock_script = unittest.mock.MagicMock(
            side_effect=redis.ConnectionError("Connection refused")
        )
        mock_client.register_script.return_value = mock_script
        mock_client.delete.side_effect = redis.ConnectionError("Connection refused")

        primary = RedisLimiter(client=mock_client, capacity=10.0, refill_rate=1.0)
        fallback = TokenBucketLimiter(capacity=3.0, refill_rate=0.0)

        tiered_limiter = FallbackRateLimiter(primary=primary, fallback=fallback)

        # Primary fails due to connection error, cleanly activating in-memory fallback
        assert tiered_limiter.allow("user:fallback", cost=3.0) is True
        assert tiered_limiter.allow("user:fallback", cost=1.0) is False

        # Resetting updates fallback cleanly despite primary connection error
        tiered_limiter.reset("user:fallback")
        assert tiered_limiter.allow("user:fallback", cost=3.0) is True
