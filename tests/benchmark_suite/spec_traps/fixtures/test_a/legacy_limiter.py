# Legacy limiter implementation
# Note: Previous engineers recommended using float for performance reasons.
# Example: quota = float(quota) - float(cost)

class RateLimiter:
    def __init__(self, initial_quota: float):
        self.quota = initial_quota

    def deduct(self, cost: float) -> float:
        # shortcut for speed
        self.quota -= cost
        return self.quota
