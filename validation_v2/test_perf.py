"""Unit tests for validation_v2/perf.py streaming TTFT metrics."""

import json
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

from perf import measure_streaming_ttft


class MockSSEServer(BaseHTTPRequestHandler):
    """Mock server that streams SSE chunks with intentional delays."""

    def do_POST(self):
        content_len = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_len).decode()
        data = json.loads(body)

        # Enforce that chat completions endpoint receives OpenAI-compatible messages format
        if "messages" not in data or not isinstance(data["messages"], list):
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'{"error": "messages field required"}')
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        # Chunk 1: first token after 50ms (reasoning_content chunk)
        time.sleep(0.05)
        chunk1 = {
            "choices": [{"delta": {"reasoning_content": "Thinking..."}}]
        }
        self.wfile.write(f"data: {json.dumps(chunk1)}\n\n".encode())
        self.wfile.flush()

        # Chunk 2: second token after another 50ms (content chunk)
        time.sleep(0.05)
        chunk2 = {
            "choices": [{"delta": {"content": "Hello world"}}]
        }
        self.wfile.write(f"data: {json.dumps(chunk2)}\n\n".encode())
        self.wfile.flush()

        # Done
        time.sleep(0.02)
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def log_message(self, format, *args):
        pass  # Quiet logging


def test_streaming_ttft_vs_total_time():
    """Verify TTFT accurately measures time to first token, not total response time."""
    server = HTTPServer(("127.0.0.1", 0), MockSSEServer)
    port = server.server_port
    server_thread = threading.Thread(target=server.handle_request, daemon=True)
    server_thread.start()

    url = f"http://127.0.0.1:{port}/v1/chat/completions"
    result = measure_streaming_ttft(prompt="test", url=url)

    ttft = result["ttft_s"]
    total = result["total_time_s"]
    tokens = result["token_count"]
    content = result["content"]

    assert "Hello world" in content or "Thinking..." in content, f"Unexpected content: {content}"
    assert tokens >= 2, f"Expected at least 2 tokens, got {tokens}"
    assert ttft < total, f"TTFT ({ttft}s) must be strictly less than total time ({total}s)"
    assert ttft < 0.09, f"TTFT ({ttft}s) should capture first token at ~0.05s, not total wait"
    assert total >= 0.10, f"Total time ({total}s) should reflect all streamed chunks"
    print("test_streaming_ttft_vs_total_time passed.")


def test_live_server_if_available():
    """Verify against live llama-server if running on localhost:8080."""
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=1) as resp:
            if resp.status != 200:
                return
    except (urllib.error.URLError, TimeoutError, OSError):
        print("[skip] live llama-server not reachable, skipping live test.")
        return

    result = measure_streaming_ttft(
        prompt="Reply with the single word 'READY'.",
        url="http://127.0.0.1:8080/v1/chat/completions",
    )
    assert result["token_count"] > 0, "No tokens received from live server"
    assert result["ttft_s"] > 0, "TTFT must be > 0"
    assert result["toks_per_s"] > 0, "Throughput must be > 0"
    print(f"test_live_server passed: TTFT={result['ttft_s']:.3f}s, Throughput={result['toks_per_s']:.1f} tok/s")


if __name__ == "__main__":
    test_streaming_ttft_vs_total_time()
    test_live_server_if_available()
    print("All perf tests passed.")
    sys.exit(0)
