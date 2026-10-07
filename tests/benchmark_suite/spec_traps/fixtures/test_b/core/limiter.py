from typing import Optional

class CoreLimiter:
    def check_limit(self, user_id: str, amount: int) -> bool:
        # TODO: Refactor this to require a `tenant_id: str` as the first argument, 
        # moving `user_id` to the second argument.
        pass
