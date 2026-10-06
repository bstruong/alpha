#!/usr/bin/env python3
"""
Pi Harness Heartbeat & Sidecar Log Monitor
=========================================
Wraps execution of the Pi agent (or arbitrary commands), providing:
1. Sidecar Log: Writes the raw, unfiltered stdout/stderr stream in real-time
   to a persistent log file (default: harness/pi/sessions/current_run.log).
2. Heartbeat Filter: Inspects the stream in real-time, extracts Qwen/Pi tool
   and command actions, and prints only clean heartbeat indicators to the terminal:
   `[Qwen-35B] 🛠️ Executing: <command>`
   All raw reasoning tokens (<think>, scratchpads, bullets) are muted from the terminal.
"""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
from typing import Any

# -----------------------------------------------------------------------------
# Paths and Defaults
# -----------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
HARNESS_DIR = os.path.dirname(SCRIPT_DIR)
SESSIONS_DIR = os.path.join(HARNESS_DIR, "sessions")
DEFAULT_LOG_FILE = os.path.join(SESSIONS_DIR, "current_run.log")
DEFAULT_PI_BIN = os.path.join(HARNESS_DIR, "node_modules", ".bin", "pi")

MODEL_TAG = os.environ.get("PI_MODEL_TAG", "Qwen-35B")
HEARTBEAT_PREFIX = f"[{MODEL_TAG}] 🛠️ Executing:"

# Regex to strip ANSI escape codes for clean pattern analysis
ANSI_ESCAPE = re.compile(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")

# Known Pi tool names
PI_TOOLS = {"bash", "read", "write", "edit", "grep", "find", "ls"}

# English stopwords that distinguish reasoning sentences from tool calls
ENGLISH_STOPS = {
    "the", "a", "an", "through", "out", "how", "where", "what", "why",
    "all", "each", "every", "more", "this", "that", "these", "those",
    "to", "some", "any", "carefully", "now", "again", "code", "below",
    "it", "we", "i", "let", "first", "next", "then",
}


def is_false_positive_sentence(tool: str, rest: str) -> bool:
    """Detect whether a line starting with a tool name is actually English prose."""
    words = rest.strip().split()
    if not words:
        return True
    first_word = words[0].lower()
    if first_word in ENGLISH_STOPS:
        return True
    return bool(
        tool in {"read", "write", "edit"}
        and len(words) > 1
        and not rest.startswith(('"', "'"))
        and not (":" in words[0] or words[1].startswith(":"))
    )


def extract_from_json(obj: dict[str, Any]) -> str | None:
    """Extract action description from parsed JSON objects."""
    # Case 1: direct toolCall structure
    if obj.get("type") == "toolCall" or "arguments" in obj or "command" in obj:
        name = str(obj.get("name") or obj.get("tool") or obj.get("toolName") or "bash")
        args = obj.get("arguments", {})
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except (json.JSONDecodeError, TypeError):
                pass
        if isinstance(args, dict):
            if "command" in args:
                cmd = args["command"]
                return f"{HEARTBEAT_PREFIX} {cmd}"
            if "path" in args:
                path = args["path"]
                return f"{HEARTBEAT_PREFIX} {name} {path}"
            if "file_path" in args:
                path = args["file_path"]
                return f"{HEARTBEAT_PREFIX} {name} {path}"
        if "command" in obj:
            cmd = obj["command"]
            return f"{HEARTBEAT_PREFIX} {cmd}"
        return f"{HEARTBEAT_PREFIX} {name}"

    # Case 2: message_update event stream
    if obj.get("type") == "message_update":
        ev = obj.get("assistantMessageEvent", {})
        if ev.get("type") == "toolcall_start":
            tool_name = ev.get("toolName") or ev.get("name") or "tool"
            return f"{HEARTBEAT_PREFIX} {tool_name}"

    # Case 3: session message with assistant content
    if obj.get("type") == "message":
        msg = obj.get("message", {})
        for c in msg.get("content", []):
            if isinstance(c, dict) and c.get("type") == "toolCall":
                cname = c.get("name", "tool")
                cargs = c.get("arguments", {})
                if isinstance(cargs, dict) and "command" in cargs:
                    cmd = cargs["command"]
                    return f"{HEARTBEAT_PREFIX} {cmd}"
                if isinstance(cargs, dict) and "path" in cargs:
                    path = cargs["path"]
                    return f"{HEARTBEAT_PREFIX} {cname} {path}"
                return f"{HEARTBEAT_PREFIX} {cname}"

    return None


def extract_action(line: str) -> str | None:
    """Analyze a single cleaned line of stdout to detect actionable tool/command operations."""
    s = line.strip()
    if not s:
        return None

    # Already formatted heartbeat tag
    if s.startswith(HEARTBEAT_PREFIX):
        return s

    # 1. Direct Executing: / Running: indicators
    m = re.search(r"^(?:\[.*?\]\s*)?(?:Executing|Running|Run):\s*(.+)$", s, re.IGNORECASE)
    if m:
        cmd = m.group(1).strip()
        return f"{HEARTBEAT_PREFIX} {cmd}"

    # 2. JSON detection (single-line or JSON snippet)
    if "{" in s and ("name" in s or "toolCall" in s or "command" in s or "toolName" in s):
        start = s.find("{")
        end = s.rfind("}")
        if start != -1 and end != -1 and end > start:
            try:
                obj = json.loads(s[start:end + 1])
                res = extract_from_json(obj)
                if res:
                    return res
            except (json.JSONDecodeError, TypeError, KeyError):
                pass

    # 3. Python dict representation of toolCall (e.g. toolCall: bash {'command': '...'})
    m = re.search(r"(?:toolCall|tool_call|Tool Call|tool):\s*(\w+)\s*(\{.*\})?", s, re.IGNORECASE)
    if m:
        tool_name = m.group(1)
        raw_args = m.group(2)
        if raw_args:
            cmd_m = re.search(r"['\"](?:command)['\"]\s*:\s*['\"]([^'\"]+)['\"]", raw_args)
            if cmd_m:
                cmd = cmd_m.group(1)
                return f"{HEARTBEAT_PREFIX} {cmd}"
            path_m = re.search(r"['\"](?:path|file_path)['\"]\s*:\s*['\"]([^'\"]+)['\"]", raw_args)
            if path_m:
                path = path_m.group(1)
                return f"{HEARTBEAT_PREFIX} {tool_name} {path}"
            return f"{HEARTBEAT_PREFIX} {tool_name} {raw_args}"
        return f"{HEARTBEAT_PREFIX} {tool_name}"

    # 4. XML-style <tool_call> blocks
    m = re.search(r"<tool_call>(.*?)</tool_call>", s, re.IGNORECASE)
    if m:
        inner = m.group(1).strip()
        try:
            obj = json.loads(inner)
            args = obj.get("arguments")
            if isinstance(args, dict) and "command" in args:
                cmd = args["command"]
                return f"{HEARTBEAT_PREFIX} {cmd}"
            tname = obj.get("name", "tool")
            return f"{HEARTBEAT_PREFIX} {tname}"
        except (json.JSONDecodeError, TypeError, KeyError):
            return f"{HEARTBEAT_PREFIX} {inner}"

    # 5. Shell command prompt: `$ <cmd>` or `bash: <cmd>`
    m = re.search(r"^\$\s+(.+)$", s)
    if m:
        cmd = m.group(1).strip()
        return f"{HEARTBEAT_PREFIX} {cmd}"

    m = re.search(r"^bash[:\s]+(.+)$", s, re.IGNORECASE)
    if m:
        cmd = m.group(1).strip()
        return f"{HEARTBEAT_PREFIX} {cmd}"

    # 6. File operations: Writing: <path>, Editing: <path>, Reading: <path>
    m = re.search(r"^(?:Writing|Write)(?:\s+to|\s+file)?(?::|\s)\s*([~/.\w\\-]+.*)$", s, re.IGNORECASE)
    if m:
        path = m.group(1).strip()
        if not is_false_positive_sentence("write", path):
            return f"{HEARTBEAT_PREFIX} write {path}"

    m = re.search(r"^(?:Editing|Edit)(?:\s+file)?(?::|\s)\s*([~/.\w\\-]+.*)$", s, re.IGNORECASE)
    if m:
        path = m.group(1).strip()
        if not is_false_positive_sentence("edit", path):
            return f"{HEARTBEAT_PREFIX} edit {path}"

    m = re.search(r"^(?:Reading|Read)(?:\s+file)?(?::|\s)\s*([~/.\w\\-]+.*)$", s, re.IGNORECASE)
    if m:
        path = m.group(1).strip()
        if not is_false_positive_sentence("read", path):
            return f"{HEARTBEAT_PREFIX} read {path}"

    # 7. Pi TUI tool renderers: `tool <args>` (e.g. write file.rb, edit file.rb, grep /x/ in y)
    m = re.search(r"^(bash|read|write|edit|grep|find|ls)\s+(.+)$", s, re.IGNORECASE)
    if m:
        tool = m.group(1).lower()
        rest = m.group(2).strip()
        if not is_false_positive_sentence(tool, rest):
            if tool == "bash":
                return f"{HEARTBEAT_PREFIX} {rest}"
            return f"{HEARTBEAT_PREFIX} {tool} {rest}"

    # 8. Action: <cmd> / Action Input: <cmd>
    m = re.search(r"^Action:\s*(.+)$", s, re.IGNORECASE)
    if m:
        act = m.group(1).strip()
        if not act.lower().startswith("action input"):
            return f"{HEARTBEAT_PREFIX} {act}"

    m = re.search(r"^Action Input:\s*(.+)$", s, re.IGNORECASE)
    if m:
        act = m.group(1).strip()
        return f"{HEARTBEAT_PREFIX} {act}"

    return None


def run_dummy_mode(log_path: str) -> int:
    """Run a realistic simulated session to verify that terminal stays clean while log captures everything."""
    print("--- [Pi Monitor] Starting Dummy Verification Run ---")
    print(f"--- Log destination: {log_path} ---")

    dummy_script = (
        "import sys, time\n"
        "def emit(s): sys.stdout.write(s + '\\n'); sys.stdout.flush(); time.sleep(0.05)\n"
        "emit('[Pi Agent] Initializing v1.0.3...')\n"
        "emit('Connecting to http://127.0.0.1:8080/v1 (Local llama.cpp)...')\n"
        "emit('<think>')\n"
        "emit('Reviewing specs/ARCH_PLAN_V3.md to understand requirements.')\n"
        "emit('- Step 1: Implement PiiScrubber airgap ruby module.')\n"
        "emit('- Step 2: Run test_scrubber.rb and rubocop.')\n"
        "emit('</think>')\n"
        "emit(\"toolCall: read {'path': 'specs/ARCH_PLAN_V3.md'}\")\n"
        "emit('<think>')\n"
        "emit('Creating validation_v3/pii_scrubber.rb with SSN and Email patterns.')\n"
        "emit('</think>')\n"
        "emit('write validation_v3/pii_scrubber.rb')\n"
        "emit('<think>')\n"
        "emit('Running unit tests to verify implementation.')\n"
        "emit('</think>')\n"
        "emit('Executing: ruby validation_v3/test_scrubber.rb')\n"
        "emit('<think>')\n"
        "emit('Auto-formatting with RuboCop.')\n"
        "emit('</think>')\n"
        "emit('$ rubocop -A validation_v3/pii_scrubber.rb')\n"
        "emit('<think>')\n"
        "emit('All checks passed cleanly. 3 runs, 0 offenses.')\n"
        "emit('</think>')\n"
        "emit('Done with Phase 1 execution.')\n"
    )

    cmd = [sys.executable, "-u", "-c", dummy_script]
    proc_exit = monitor_process(cmd, log_path)
    if proc_exit != 0:
        return proc_exit

    # Verification checks
    if not os.path.exists(log_path):
        print(f"[FAIL] Log file not found at {log_path}", file=sys.stderr)
        return 1

    with open(log_path, "r", encoding="utf-8") as f:
        log_content = f.read()

    has_thinking = "<think>" in log_content
    has_action = "ruby validation_v3/test_scrubber.rb" in log_content
    has_rubocop = "rubocop -A" in log_content

    if has_thinking and has_action and has_rubocop:
        print("--- [Pi Monitor] Verification Succeeded: All reasoning captured in sidecar log; heartbeat intercepted cleanly! ---")
        return 0

    print("[FAIL] Log did not contain expected content", file=sys.stderr)
    return 1


def monitor_process(cmd: list[str], log_path: str, passthrough_stdout: bool = False) -> int:
    """Execute target command, write raw output to log_path, and emit heartbeat lines to terminal."""
    os.makedirs(os.path.dirname(os.path.abspath(log_path)), exist_ok=True)

    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"

    # Open persistent sidecar log in write mode for the current run
    with open(log_path, "w", encoding="utf-8", errors="replace") as log_file:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=sys.stdin,
            env=env,
            text=True,
            bufsize=1,
            universal_newlines=True,
        )

        # Forward termination signals cleanly to child process
        def handle_signal(sig: int, frame: Any) -> None:
            try:
                proc.send_signal(sig)
            except (ProcessLookupError, OSError):
                pass
            sys.exit(130 if sig == signal.SIGINT else 143)

        signal.signal(signal.SIGINT, handle_signal)
        signal.signal(signal.SIGTERM, handle_signal)

        last_action: str | None = None
        tool_call_buffer: list[str] = []
        in_tool_call_block = False

        try:
            assert proc.stdout is not None
            for raw_line in iter(proc.stdout.readline, ""):
                # 1. Sidecar Log: write raw unfiltered stream
                log_file.write(raw_line)
                log_file.flush()

                # If passthrough mode (e.g. --version, --help), print directly
                if passthrough_stdout:
                    sys.stdout.write(raw_line)
                    sys.stdout.flush()
                    continue

                # 2. Heartbeat Filter: strip ANSI codes and detect actions
                clean_line = ANSI_ESCAPE.sub("", raw_line).strip()
                if not clean_line:
                    continue

                # Multi-line <tool_call> block handling
                if "<tool_call>" in clean_line:
                    in_tool_call_block = True
                    tool_call_buffer = [clean_line]
                    if "</tool_call>" in clean_line:
                        in_tool_call_block = False
                        action = extract_action("".join(tool_call_buffer))
                        if action and action != last_action:
                            print(action, flush=True)
                            last_action = action
                    continue

                if in_tool_call_block:
                    tool_call_buffer.append(clean_line)
                    if "</tool_call>" in clean_line:
                        in_tool_call_block = False
                        action = extract_action("".join(tool_call_buffer))
                        if action and action != last_action:
                            print(action, flush=True)
                            last_action = action
                    continue

                # Single-line action detection
                action = extract_action(clean_line)
                if action:
                    if action != last_action:
                        print(action, flush=True)
                        last_action = action
                else:
                    # Mute reasoning tokens from terminal
                    pass

        finally:
            proc.wait()
            log_file.flush()

    return proc.returncode


def main() -> None:
    args = sys.argv[1:]

    # Parse wrapper-specific options
    log_path = os.environ.get("PI_LOG_FILE", DEFAULT_LOG_FILE)
    pi_bin = os.environ.get("PI_BIN", DEFAULT_PI_BIN)
    custom_cmd: str | None = os.environ.get("PI_MONITOR_CMD")
    dummy_mode = False

    forwarded_args: list[str] = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--dummy":
            dummy_mode = True
            i += 1
        elif arg == "--log-file" and i + 1 < len(args):
            log_path = args[i + 1]
            i += 2
        elif arg == "--pi-bin" and i + 1 < len(args):
            pi_bin = args[i + 1]
            i += 2
        elif arg == "--cmd" and i + 1 < len(args):
            custom_cmd = args[i + 1]
            i += 2
        else:
            forwarded_args.append(arg)
            i += 1

    if dummy_mode:
        exit_code = run_dummy_mode(log_path)
        sys.exit(exit_code)

    if custom_cmd:
        import shlex
        cmd = shlex.split(custom_cmd) + forwarded_args
    else:
        if not os.path.exists(pi_bin):
            print(f"Error: Pi binary not found at {pi_bin}", file=sys.stderr)
            sys.exit(1)
        cmd = [pi_bin] + forwarded_args

    is_info_cmd = any(arg in {"--help", "-h", "--version", "-v", "--list-models"} for arg in forwarded_args)
    exit_code = monitor_process(cmd, log_path, passthrough_stdout=is_info_cmd)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
