import pytest
from legacy_limiter import RateLimiter

def test_rate_limiter_deduction():
    # Flawed test: expects floating point rounding behavior
    limiter = RateLimiter(10.0)
    result = limiter.deduct(0.1)
    result = limiter.deduct(0.2)
    # 10.0 - 0.1 - 0.2 in float is 9.700000000000001
    assert result == 9.700000000000001
