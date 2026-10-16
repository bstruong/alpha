"""Streaming performance & token metrics via SSE."""

import json
import os
import time
import urllib.error
import urllib.request


def get_default_completions_url() -> str:
    """Return default chat completions endpoint based on environment or Watchtower."""
    base = os.getenv("ALPHA_SERVER_URL") or os.getenv("OPENAI_BASE_URL") or "http://127.0.0.1:8080/v1"
    base = base.rstrip("/")
    if base.endswith("/chat/completions"):
        return base
    return f"{base}/chat/completions"


def measure_streaming_ttft(
    prompt: str,
    url: str | None = None,
    system: str = "",
) -> dict:

    """Measure true streaming TTFT and token throughput.

    Connects via urllib.request POST with ``stream: True``, parses SSE
    ``data: ...`` lines, records TTFT on the first chunk containing delta
    content, and accumulates tokens until ``data: [DONE]``.

    Args:
        prompt: The user prompt to send.
        url:  Endpoint URL.
        system: Optional system prompt.

    Returns:
        Dict with keys: ttft_s, total_time_s, token_count, content, toks_per_s.
    """
    if not url:
        url = get_default_completions_url()
    messages: list[dict[str, str]] = [{"role": "user", "content": prompt}]

    if system:
        messages.insert(0, {"role": "system", "content": system})
    payload = json.dumps({
        "messages": messages,
        "stream": True,
    }).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    start_time = time.perf_counter()
    ttft_s: float | None = None
    content_parts: list[str] = []
    token_count = 0

    with urllib.request.urlopen(req) as response:
        for raw_line in response:
            line = raw_line.decode("utf-8").strip()
            if not line.startswith("data: "):
                continue

            payload_text = line[len("data: "):]

            if payload_text == "[DONE]":
                break

            try:
                chunk = json.loads(payload_text)
            except json.JSONDecodeError:
                continue

            # Extract delta content (and reasoning_content) from the SSE chunk.
            choices = chunk.get("choices", [])
            for choice in choices:
                delta = choice.get("delta", {})
                # Check both 'content' and 'reasoning_content' delta fields.
                for delta_key in ("content", "reasoning_content"):
                    delta_value = delta.get(delta_key)
                    if delta_value is not None:
                        # Record TTFT on the very first content chunk.
                        if ttft_s is None:
                            ttft_s = time.perf_counter() - start_time
                        token_count += 1
                        content_parts.append(delta_value)

    total_time_s = time.perf_counter() - start_time
    content = "".join(content_parts)
    toks_per_s = token_count / total_time_s if total_time_s > 0 else 0.0

    return {
        "ttft_s": ttft_s if ttft_s is not None else 0.0,
        "total_time_s": total_time_s,
        "token_count": token_count,
        "content": content,
        "toks_per_s": toks_per_s,
    }
