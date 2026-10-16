from storage.redis import RedisStorage

class HttpMiddleware:
    def __init__(self, storage: RedisStorage):
        self.storage = storage

    def handle_request(self, request):
        user_id = request.get("user_id")
        # Assume tenant_id is available in the request
        tenant_id = request.get("tenant_id", "default_tenant")
        
        # We need to pass tenant_id down the chain once refactored, or update storage
        # Currently storage.process_request only takes user_id and amount
        self.storage.process_request(user_id, 1)
