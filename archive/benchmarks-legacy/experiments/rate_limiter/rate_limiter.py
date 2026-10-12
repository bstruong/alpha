"""High-performance concurrent Token-Bucket Rate Limiter with Redis distributed fallback.

This module provides thread-safe, scalable rate limiting for local and distributed
environments, featuring per-bucket synchronization, clock-skew mitigation, bounded
memory semantics, and atomic Redis Lua execution with server-authoritative timestamps.
"""

from __future__ import annotations

import logging
import math
import threading
import time
from abc import ABC, abstractmethod
from collections import OrderedDict
from collections.abc import Callable
from typing import Any, Final

import redis

logger = logging.getLogger(__name__)


class RateLimiterError(Exception):
    """Base exception for rate limiter operations."""


class RateLimiterBackendError(RateLimiterError):
    """Raised when an external rate limiter backend fails."""


class RateLimiter(ABC):
    """Abstract base class defining the contract for rate limiter implementations."""

    @abstractmethod
    def allow(self, key: str, cost: float = 1.0) -> bool:
        """Check if `cost` tokens can be consumed for the specified `key`.

        Args:
            key: Unique identifier for the rate-limited resource/client.
            cost: Number of tokens requested (must be strictly positive).

        Returns:
            True if permitted and tokens were deducted; False otherwise.

        Raises:
            ValueError: If key is invalid or cost is not strictly positive.
        """

    @abstractmethod
    def reset(self, key: str) -> None:
        """Reset the rate limit state for `key`, restoring it to full capacity.

        Args:
            key: Unique identifier for the rate-limited resource/client.

        Raises:
            ValueError: If key is invalid.
        """


class _TokenBucket:
    """Internal bucket storing token state and dedicated synchronization per key.

    Per-bucket locking eliminates global lock contention across distinct keys.
    """

    __slots__ = (
        "_capacity",
        "_last_access",
        "_last_refill",
        "_lock",
        "_refill_rate",
        "_tokens",
    )

    def __init__(
        self, capacity: float, refill_rate: float, initial_time: float
    ) -> None:
        self._capacity: Final[float] = capacity
        self._refill_rate: Final[float] = refill_rate
        self._tokens: float = capacity
        self._last_refill: float = initial_time
        self._last_access: float = initial_time
        self._lock = threading.Lock()

    def allow(self, cost: float, now: float) -> bool:
        """Attempt to consume `cost` tokens with clock-skew resilience."""
        with self._lock:
            self._last_access = now
            elapsed = now - self._last_refill

            if elapsed < 0.0:
                # Clock skew detected (system or monotonic clock jumped backwards).
                # Clamp elapsed to 0 to prevent artificial token drain.
                # Invariant: DO NOT update _last_refill to the earlier timestamp;
                # preserving the higher baseline prevents an artificial double-refill burst
                # when time advances back to normal.
                logger.warning(
                    "Clock skew detected in token bucket",
                    extra={
                        "elapsed": elapsed,
                        "now": now,
                        "last_refill": self._last_refill,
                    },
                )
                elapsed = 0.0
            else:
                self._last_refill = now

            # Dynamic continuous refill capped at capacity
            self._tokens = min(
                self._capacity, self._tokens + (elapsed * self._refill_rate)
            )

            if self._tokens >= cost:
                self._tokens -= cost
                return True

            return False

    def reset(self, now: float) -> None:
        """Atomically restore bucket to full capacity."""
        with self._lock:
            self._tokens = self._capacity
            self._last_refill = now
            self._last_access = now

    def get_tokens(self, now: float) -> float:
        """Return the current token balance after calculating pending refill."""
        with self._lock:
            elapsed = max(0.0, now - self._last_refill)
            return min(self._capacity, self._tokens + (elapsed * self._refill_rate))

    def is_stale(self, now: float, ttl: float) -> bool:
        """Determine if bucket is full and idle, making it safe for eviction."""
        with self._lock:
            elapsed = max(0.0, now - self._last_refill)
            current_tokens = min(
                self._capacity, self._tokens + (elapsed * self._refill_rate)
            )
            is_full = current_tokens >= self._capacity
            is_idle = (now - self._last_access) >= ttl
            return is_full and is_idle


class TokenBucketLimiter(RateLimiter):
    """In-memory concurrent Token-Bucket Rate Limiter with per-bucket locking.

    Thread safety is achieved using a two-tier locking model:
    1. A registry-level lock (`_registry_lock`) protects dictionary lookup and key insertions.
    2. An individual lock per `_TokenBucket` protects token refill and balance mutations.
    This guarantees zero lock contention between concurrent operations targeting distinct keys.

    Memory consumption is strictly bounded via an LRU eviction strategy combined with
    stale-bucket pruning when cardinality reaches `max_keys`.
    """

    def __init__(
        self,
        capacity: float,
        refill_rate: float,
        *,
        max_keys: int = 100_000,
        stale_ttl: float | None = None,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        """Initialize the TokenBucketLimiter.

        Args:
            capacity: Maximum burst capacity (must be strictly positive).
            refill_rate: Number of tokens replenished per second (must be strictly positive).
            max_keys: Maximum unique keys retained before LRU/stale eviction triggers.
            stale_ttl: Inactive seconds before a full bucket is eligible for pruning.
            clock: Time source returning seconds as float (defaults to time.monotonic).

        Raises:
            ValueError: If capacity, refill_rate, or max_keys are not strictly positive.
        """
        if (
            not isinstance(capacity, (int, float))
            or isinstance(capacity, bool)
            or capacity <= 0.0
            or math.isnan(capacity)
            or math.isinf(capacity)
        ):
            raise ValueError(
                f"Capacity must be a strictly positive finite number, got {capacity!r}"
            )
        if (
            not isinstance(refill_rate, (int, float))
            or isinstance(refill_rate, bool)
            or refill_rate < 0.0
            or math.isnan(refill_rate)
            or math.isinf(refill_rate)
        ):
            raise ValueError(
                f"Refill rate must be a non-negative finite number, got {refill_rate!r}"
            )
        if not isinstance(max_keys, int) or isinstance(max_keys, bool) or max_keys <= 0:
            raise ValueError(
                f"max_keys must be a strictly positive integer, got {max_keys!r}"
            )

        self._capacity: Final[float] = float(capacity)
        self._refill_rate: Final[float] = float(refill_rate)
        self._max_keys: Final[int] = max_keys
        self._clock: Final[Callable[[], float]] = clock

        # Default stale_ttl: twice the time required to refill from empty to full, minimum 60s
        if stale_ttl is not None:
            if (
                not isinstance(stale_ttl, (int, float))
                or isinstance(stale_ttl, bool)
                or stale_ttl <= 0.0
                or math.isnan(stale_ttl)
                or math.isinf(stale_ttl)
            ):
                raise ValueError(
                    f"stale_ttl must be a strictly positive finite number, got {stale_ttl!r}"
                )
            self._stale_ttl: Final[float] = float(stale_ttl)
        else:
            if self._refill_rate > 0.0:
                refill_duration = self._capacity / self._refill_rate
                self._stale_ttl = max(60.0, refill_duration * 2.0)
            else:
                self._stale_ttl = 3600.0

        self._registry_lock = threading.Lock()
        self._buckets: OrderedDict[str, _TokenBucket] = OrderedDict()

    @property
    def capacity(self) -> float:
        """Return the maximum token capacity."""
        return self._capacity

    @property
    def refill_rate(self) -> float:
        """Return the token refill rate per second."""
        return self._refill_rate

    def _validate_inputs(self, key: str, cost: float) -> None:
        """Validate key and cost arguments against strict contract invariants."""
        if not isinstance(key, str) or not key:
            raise ValueError(f"Key must be a non-empty string, got {key!r}")
        if (
            not isinstance(cost, (int, float))
            or isinstance(cost, bool)
            or cost <= 0.0
            or math.isnan(cost)
            or math.isinf(cost)
        ):
            raise ValueError(
                f"Cost must be a strictly positive finite number, got {cost!r}"
            )

    def _evict_stale_or_lru(self, now: float) -> None:
        """Evict stale full buckets or fallback to LRU key eviction.

        Must be called while holding `_registry_lock`.
        """
        # Pass 1: Prune up to 10 least-recently-used stale buckets that are already full
        pruned_keys: list[str] = []
        for candidate_key, candidate_bucket in self._buckets.items():
            if candidate_bucket.is_stale(now, self._stale_ttl):
                pruned_keys.append(candidate_key)
                if len(pruned_keys) >= 10:
                    break

        for pk in pruned_keys:
            del self._buckets[pk]

        # Pass 2: If still at capacity, discard oldest LRU entry
        if len(self._buckets) >= self._max_keys:
            self._buckets.popitem(last=False)

    def allow(self, key: str, cost: float = 1.0) -> bool:
        """Check and consume tokens for `key` using per-bucket synchronization."""
        self._validate_inputs(key, cost)
        now = self._clock()

        # Step 1: Retrieve or instantiate bucket under short registry lock
        with self._registry_lock:
            bucket = self._buckets.get(key)
            if bucket is None:
                if len(self._buckets) >= self._max_keys:
                    self._evict_stale_or_lru(now)
                bucket = _TokenBucket(self._capacity, self._refill_rate, now)
                self._buckets[key] = bucket
            self._buckets.move_to_end(key)

        # Step 2: Acquire per-bucket lock outside of global registry lock
        return bucket.allow(cost, now)

    def reset(self, key: str) -> None:
        """Reset the specified key to its full burst capacity."""
        if not isinstance(key, str) or not key:
            raise ValueError(f"Key must be a non-empty string, got {key!r}")

        now = self._clock()
        with self._registry_lock:
            bucket = self._buckets.get(key)

        if bucket is not None:
            bucket.reset(now)

    def get_tokens(self, key: str) -> float | None:
        """Return the current available tokens for `key`, or None if untracked."""
        if not isinstance(key, str) or not key:
            raise ValueError(f"Key must be a non-empty string, got {key!r}")

        now = self._clock()
        with self._registry_lock:
            bucket = self._buckets.get(key)

        if bucket is None:
            return None
        return bucket.get_tokens(now)

    def cleanup(self) -> int:
        """Manually purge all stale buckets currently at capacity.

        Returns:
            Number of purged keys.
        """
        now = self._clock()
        to_delete: list[str] = []
        with self._registry_lock:
            for k, b in self._buckets.items():
                if b.is_stale(now, self._stale_ttl):
                    to_delete.append(k)
            for k in to_delete:
                del self._buckets[k]
        return len(to_delete)

    def __len__(self) -> int:
        """Return the number of currently tracked buckets."""
        with self._registry_lock:
            return len(self._buckets)


# ---------------------------------------------------------------------------
# Redis Distributed Fallback Limiter
# ---------------------------------------------------------------------------

# Atomic Redis Lua script implementing the token bucket algorithm.
# Uses `redis.call('TIME')` directly on the Redis server to prevent client clock skew.
REDIS_TOKEN_BUCKET_LUA: Final[str] = """
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill_rate = tonumber(ARGV[2])
local cost = tonumber(ARGV[3])
local ttl_seconds = tonumber(ARGV[4])

-- Retrieve authoritative Redis server time to prevent client-side clock drift
local rtime = redis.call('TIME')
local now = tonumber(rtime[1]) + (tonumber(rtime[2]) / 1000000)

local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
local tokens = tonumber(bucket[1])
local last_refill = tonumber(bucket[2])

if tokens == nil then
    tokens = capacity
    last_refill = now
end

-- Clock skew mitigation: if server clock moved backwards, clamp elapsed to 0
local elapsed = now - last_refill
if elapsed < 0 then
    elapsed = 0
else
    last_refill = now
end

-- Dynamic refill bounded by capacity
tokens = math.min(capacity, tokens + (elapsed * refill_rate))

if tokens >= cost then
    tokens = tokens - cost
    redis.call('HSET', key, 'tokens', tokens, 'last_refill', last_refill)
    redis.call('EXPIRE', key, ttl_seconds)
    return 1
else
    redis.call('HSET', key, 'tokens', tokens, 'last_refill', last_refill)
    redis.call('EXPIRE', key, ttl_seconds)
    return 0
end
"""


class RedisLimiter(RateLimiter):
    """Distributed rate limiter backed by Redis and executed via atomic Lua script.

    Eliminates cross-node clock skew by resolving timestamps on the Redis server via
    `redis.call('TIME')`. Keys automatically expire when idle to avoid unbounded memory growth.
    """

    def __init__(
        self,
        client: redis.Redis[Any],
        capacity: float,
        refill_rate: float,
        *,
        prefix: str = "ratelimit:",
        key_ttl: int | None = None,
    ) -> None:
        """Initialize the RedisLimiter.

        Args:
            client: Configured `redis.Redis` instance.
            capacity: Maximum burst capacity (must be strictly positive).
            refill_rate: Number of tokens replenished per second (must be strictly positive).
            prefix: Key namespace prefix to prevent collision in shared Redis databases.
            key_ttl: Key expiration in seconds (defaults to twice refill time, minimum 60s).

        Raises:
            ValueError: If capacity or refill_rate are invalid.
        """
        if (
            not isinstance(capacity, (int, float))
            or isinstance(capacity, bool)
            or capacity <= 0.0
            or math.isnan(capacity)
            or math.isinf(capacity)
        ):
            raise ValueError(
                f"Capacity must be a strictly positive finite number, got {capacity!r}"
            )
        if (
            not isinstance(refill_rate, (int, float))
            or isinstance(refill_rate, bool)
            or refill_rate < 0.0
            or math.isnan(refill_rate)
            or math.isinf(refill_rate)
        ):
            raise ValueError(
                f"Refill rate must be a non-negative finite number, got {refill_rate!r}"
            )

        self._client: Final[redis.Redis[Any]] = client
        self._capacity: Final[float] = float(capacity)
        self._refill_rate: Final[float] = float(refill_rate)
        self._prefix: Final[str] = prefix

        if key_ttl is not None:
            if (
                not isinstance(key_ttl, int)
                or isinstance(key_ttl, bool)
                or key_ttl <= 0
            ):
                raise ValueError(
                    f"key_ttl must be a strictly positive integer, got {key_ttl!r}"
                )
            self._key_ttl: Final[int] = key_ttl
        else:
            if self._refill_rate > 0.0:
                refill_duration = self._capacity / self._refill_rate
                self._key_ttl = max(60, math.ceil(refill_duration * 2.0))
            else:
                self._key_ttl = 86400

        # Register the script once with Redis (EVALSHA with fallback to EVAL)
        self._script = self._client.register_script(REDIS_TOKEN_BUCKET_LUA)

    def _make_key(self, key: str) -> str:
        return f"{self._prefix}{key}"

    def allow(self, key: str, cost: float = 1.0) -> bool:
        """Check and consume tokens in Redis atomically."""
        if not isinstance(key, str) or not key:
            raise ValueError(f"Key must be a non-empty string, got {key!r}")
        if (
            not isinstance(cost, (int, float))
            or isinstance(cost, bool)
            or cost <= 0.0
            or math.isnan(cost)
            or math.isinf(cost)
        ):
            raise ValueError(
                f"Cost must be a strictly positive finite number, got {cost!r}"
            )

        redis_key = self._make_key(key)
        try:
            result = self._script(
                keys=[redis_key],
                args=[self._capacity, self._refill_rate, cost, self._key_ttl],
            )
            return bool(int(result) == 1)
        except redis.RedisError as exc:
            logger.exception(
                "Redis rate limiter Lua execution failure",
                extra={"key": key, "redis_key": redis_key, "error": str(exc)},
            )
            raise RateLimiterBackendError(
                f"Redis rate limiter failure for key {key!r}: {exc}"
            ) from exc

    def reset(self, key: str) -> None:
        """Reset the rate limit state in Redis by deleting the bucket key."""
        if not isinstance(key, str) or not key:
            raise ValueError(f"Key must be a non-empty string, got {key!r}")

        redis_key = self._make_key(key)
        try:
            self._client.delete(redis_key)
        except redis.RedisError as exc:
            logger.exception(
                "Redis rate limiter key reset failure",
                extra={"key": key, "redis_key": redis_key, "error": str(exc)},
            )
            raise RateLimiterBackendError(
                f"Redis reset failure for key {key!r}: {exc}"
            ) from exc


class FallbackRateLimiter(RateLimiter):
    """Tiered rate limiter delegating to primary (e.g. Redis) and falling back to in-memory."""

    def __init__(self, primary: RateLimiter, fallback: RateLimiter) -> None:
        """Initialize with primary and fallback limiters."""
        self._primary: Final[RateLimiter] = primary
        self._fallback: Final[RateLimiter] = fallback

    @property
    def primary(self) -> RateLimiter:
        """Return the primary limiter."""
        return self._primary

    @property
    def fallback(self) -> RateLimiter:
        """Return the fallback limiter."""
        return self._fallback

    def allow(self, key: str, cost: float = 1.0) -> bool:
        """Attempt primary limiter; gracefully fallback to secondary on backend failure."""
        try:
            return self._primary.allow(key, cost)
        except RateLimiterBackendError as exc:
            logger.warning(
                "Primary rate limiter backend error, activating fallback",
                extra={"key": key, "cost": cost, "error": str(exc)},
            )
            return self._fallback.allow(key, cost)

    def reset(self, key: str) -> None:
        """Reset state across both primary and fallback backends."""
        try:
            self._primary.reset(key)
        except RateLimiterBackendError as exc:
            logger.warning(
                "Primary rate limiter reset error, resetting fallback only",
                extra={"key": key, "error": str(exc)},
            )
        self._fallback.reset(key)
