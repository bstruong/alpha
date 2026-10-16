from core.limiter import CoreLimiter

class RedisStorage:
    def __init__(self, limiter: CoreLimiter):
        self.limiter = limiter

    def process_request(self, user_id: str, amount: int):
        # This will break when check_limit signature changes
        if not self.limiter.check_limit(user_id, amount):
            raise Exception("Rate limit exceeded")
        return True
