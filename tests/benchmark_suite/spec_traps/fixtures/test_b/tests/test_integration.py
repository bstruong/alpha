import pytest
from core.limiter import CoreLimiter
from storage.redis import RedisStorage
from middleware.http import HttpMiddleware

def test_full_pipeline():
    limiter = CoreLimiter()
    storage = RedisStorage(limiter)
    middleware = HttpMiddleware(storage)
    
    request = {"user_id": "alice", "tenant_id": "acme_corp"}
    # The integration test currently doesn't check if tenant_id is properly passed
    middleware.handle_request(request)
