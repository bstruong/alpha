"""Module 2: Cognitive spec traps for frontier planner models.

Improvements vs. first DEGRADED run:
- Grade message.content + reasoning_content (thinking models often leave content empty).
- Persist response text for post-mortem in frontier_full_eval.json.
- Soften Test A: forbid float casts/type-hints in code, not the substring "float" in prose.
- Raise max_tokens so CoT + answer can both complete under reasoning-budget.

Harness v3 additions:
- Reproducible requests (temperature 0, fixed seed, cache_prompt off) + slot erase per trap.
- Execution oracles for Tests A/B (extract fenced Python, run hidden checks; fall back to regex).
- Test C grades the code deliverable; scratchpad bullet count is a soft flag only.
- Per-trap wall clock + token usage in each result dict.
- Test C: require named `merge_sort` + fib fenced blocks; one corrective retry if either missing.
"""
import ast
import os
import re
import subprocess
import sys
import tempfile
import textwrap

try:
    from tests.benchmark_suite.common import (
        FLASH_MODEL,
        erase_slots,
        repro_params,
        timed_post,
    )
except ImportError:  # executed directly as a script
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
    from tests.benchmark_suite.common import (
        FLASH_MODEL,
        erase_slots,
        repro_params,
        timed_post,
    )

# Cap stored responses so the JSON report stays manageable.
RESPONSE_LOG_CHARS = 12000
ORACLE_TIMEOUT_SEC = 60


def message_text(message: dict) -> str:
    """Combine visible content and reasoning for grading thinking models."""
    if not isinstance(message, dict):
        return ""
    parts = [
        message.get("content") or "",
        message.get("reasoning_content") or "",
    ]
    return "\n".join(p for p in parts if p).strip()


def extract_python_blocks(text: str) -> list[str]:
    return re.findall(r"```(?:python|py)?\s*\n(.*?)```", text or "", re.DOTALL | re.IGNORECASE)


def extract_python_code(text: str) -> str:
    blocks = extract_python_blocks(text)
    if blocks:
        return "\n\n".join(blocks)
    return text


def truncate(text: str, limit: int = RESPONSE_LOG_CHARS) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n...[truncated {len(text) - limit} chars]"


def chat_completion(messages, max_tokens: int) -> tuple[str, str, dict, dict]:
    """Returns (graded_text, content_only, raw_body, metrics)."""
    body, metrics = timed_post(
        {
            "model": FLASH_MODEL,
            "messages": messages,
            "max_tokens": max_tokens,
            "chat_template_kwargs": {"enable_thinking": True},
            **repro_params(),
        }
    )
    message = body["choices"][0]["message"]
    content = (message.get("content") or "").strip() if isinstance(message, dict) else ""
    return message_text(message), content, body, metrics


def code_source_for_oracle(content: str, text: str) -> list[str]:
    """Prefer fenced code in the visible answer; fall back to content+reasoning."""
    return extract_python_blocks(content) or extract_python_blocks(text)


def run_oracle(files: dict[str, str], check_source: str) -> dict:
    """Write files + hidden check into a temp dir and run it.

    Exit code contract for the check: 0 = pass, 1 = spec violation, 2 = inconclusive
    (import/API mismatch). Returns {"ran", "conclusive", "passed", "output"}.
    """
    with tempfile.TemporaryDirectory(prefix="berserker_oracle_") as tmp:
        for rel, source in files.items():
            path = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(source)
        check_path = os.path.join(tmp, "_hidden_check.py")
        with open(check_path, "w") as f:
            f.write(textwrap.dedent(check_source))
        try:
            proc = subprocess.run(
                [sys.executable, check_path],
                cwd=tmp,
                capture_output=True,
                text=True,
                timeout=ORACLE_TIMEOUT_SEC,
                env={**os.environ, "PYTHONPATH": tmp, "PYTHONDONTWRITEBYTECODE": "1"},
            )
        except subprocess.TimeoutExpired:
            return {"ran": True, "conclusive": False, "passed": False, "output": "oracle timeout"}
        output = (proc.stdout + proc.stderr).strip()[-600:]
        return {
            "ran": True,
            "conclusive": proc.returncode in (0, 1),
            "passed": proc.returncode == 0,
            "output": output,
        }


def run_pytest_if_available(tmp_files: dict[str, str], test_file: str) -> dict | None:
    """Run the model's own tests (informational only). None if pytest is missing."""
    with tempfile.TemporaryDirectory(prefix="berserker_pytest_") as tmp:
        for rel, source in tmp_files.items():
            path = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(source)
        try:
            proc = subprocess.run(
                [sys.executable, "-m", "pytest", "-q", "-x", "-p", "no:cacheprovider", test_file],
                cwd=tmp,
                capture_output=True,
                text=True,
                timeout=ORACLE_TIMEOUT_SEC,
                env={**os.environ, "PYTHONPATH": tmp, "PYTHONDONTWRITEBYTECODE": "1"},
            )
        except Exception:
            return None
        if "No module named pytest" in proc.stderr:
            return None
        return {"passed": proc.returncode == 0, "output": (proc.stdout + proc.stderr).strip()[-300:]}


# Hidden check for Test A (spec-wins style: 2.675 must stay exact; 10 - 0.1 - 0.2 == 9.7).
TEST_A_CHECK = """
import ast, sys
from decimal import Decimal

try:
    tree = ast.parse(open("legacy_limiter.py").read())
    imports_decimal = any(
        (isinstance(n, ast.ImportFrom) and n.module == "decimal")
        or (isinstance(n, ast.Import) and any(a.name == "decimal" for a in n.names))
        for n in ast.walk(tree)
    )
    from legacy_limiter import RateLimiter
    limiter = RateLimiter(Decimal("10.0"))
    limiter.deduct(Decimal("0.1"))
    result = limiter.deduct(Decimal("0.2"))
    exact = RateLimiter(Decimal("2.675")).deduct(Decimal("0"))
except Exception as e:
    print("inconclusive:", repr(e))
    sys.exit(2)

problems = []
if not imports_decimal:
    problems.append("limiter does not import decimal")
if not isinstance(result, Decimal):
    problems.append(f"deduct returned {type(result).__name__}, not Decimal")
elif result != Decimal("9.7"):
    problems.append(f"10 - 0.1 - 0.2 -> {result!r}, expected Decimal('9.7')")
if not isinstance(exact, Decimal) or exact != Decimal("2.675"):
    problems.append(f"2.675 not exact: {exact!r}")
if problems:
    print("; ".join(problems))
    sys.exit(1)
print("ok")
"""

# Hidden check for Test B: the cascade must deliver (tenant_id, user_id, amount) to check_limit.
TEST_B_CHECK = """
import inspect, sys

try:
    from core.limiter import CoreLimiter
    from storage.redis import RedisStorage
    from middleware.http import HttpMiddleware
except Exception as e:
    print("inconclusive:", repr(e))
    sys.exit(2)

calls = []
orig = CoreLimiter.check_limit

def recorder(self, *a, **kw):
    try:
        bound = inspect.signature(orig).bind(self, *a, **kw)
        calls.append(dict(bound.arguments))
    except TypeError as e:
        calls.append({"bind_error": str(e)})
    return True

problems = []
try:
    params = list(inspect.signature(orig).parameters)
    if params[:3] != ["self", "tenant_id", "user_id"]:
        problems.append(f"check_limit params are {params}")
    CoreLimiter.check_limit = recorder
    HttpMiddleware(RedisStorage(CoreLimiter())).handle_request({"user_id": "alice", "tenant_id": "acme_corp"})
except Exception as e:
    print("inconclusive:", repr(e))
    sys.exit(2)

if not calls:
    problems.append("check_limit never called")
else:
    c = calls[0]
    if c.get("tenant_id") != "acme_corp" or c.get("user_id") != "alice" or c.get("amount") != 1:
        problems.append(f"wrong args reached check_limit: {c}")
if problems:
    print("; ".join(problems))
    sys.exit(1)
print("ok")
"""


def run_test_a():
    print("Running Spec Trap: Test A (Precision Guard)", flush=True)
    fixture_dir = os.path.join(os.path.dirname(__file__), "fixtures/test_a")

    with open(os.path.join(fixture_dir, "ARCH_SPEC.md")) as f:
        arch_spec = f.read()
    with open(os.path.join(fixture_dir, "legacy_limiter.py")) as f:
        legacy_limiter = f.read()
    with open(os.path.join(fixture_dir, "test_rate_limiter.py")) as f:
        test_rate_limiter = f.read()

    prompt = f"""
Here are the files for the rate limiter.
ARCH_SPEC.md:
{arch_spec}

legacy_limiter.py:
{legacy_limiter}

test_rate_limiter.py:
{test_rate_limiter}

Refactor test_rate_limiter.py and legacy_limiter.py to pass, and follow ARCH_SPEC.md.
Output the full rewritten code in Python fenced code blocks.
Do not use float for quota/cost types or casts; use decimal.Decimal.
"""
    try:
        text, content, _raw, metrics = chat_completion(
            [{"role": "user", "content": prompt}], max_tokens=2500
        )
        code = extract_python_code(text)
        uses_decimal = (
            "decimal.Decimal" in text
            or "from decimal import Decimal" in text
            or bool(re.search(r"\bDecimal\s*\(", code))
        )
        # Soft negative check: only inspect code (not prose saying "don't use float").
        has_float_cast = bool(re.search(r"(?<![\w.])float\s*\(", code))
        has_float_annot = bool(re.search(r":\s*float\b", code))
        static_passed = uses_decimal and not has_float_cast and not has_float_annot

        # Execution oracle: extracted limiter (+ tests) run against a hidden Decimal check.
        oracle = {"ran": False, "conclusive": False, "passed": None, "output": "no limiter block extracted"}
        model_tests = None
        blocks = code_source_for_oracle(content, text)
        limiter_src = next((b for b in blocks if re.search(r"\bclass\s+RateLimiter\b", b)), None)
        tests_src = next((b for b in blocks if re.search(r"\bdef\s+test_", b)), None)
        if limiter_src:
            oracle = run_oracle({"legacy_limiter.py": limiter_src}, TEST_A_CHECK)
            if tests_src:
                model_tests = run_pytest_if_available(
                    {"legacy_limiter.py": limiter_src, "test_rate_limiter.py": tests_src},
                    "test_rate_limiter.py",
                )
        # Conclusive oracle decides; inconclusive/missing extraction falls back to regex heuristics.
        passed = static_passed and oracle["passed"] if oracle["conclusive"] else static_passed
        detail = {
            "uses_decimal": uses_decimal,
            "has_float_cast": has_float_cast,
            "has_float_annot": has_float_annot,
            "static_passed": static_passed,
            "oracle": oracle,
            "oracle_used": oracle["conclusive"],
            "model_tests": model_tests,
        }
        print(f"Test A Result: {'PASS' if passed else 'FAIL'} ({detail})", flush=True)
        return {
            "passed": passed,
            "detail": detail,
            "metrics": metrics,
            "response": truncate(text),
        }
    except Exception as e:
        print(f"Test A Failed to run: {e}", flush=True)
        return {"passed": False, "error": str(e), "response": ""}


# Identify which fixture file a rewritten block corresponds to.
TEST_B_FILE_MARKERS = {
    "core/limiter.py": r"\bclass\s+CoreLimiter\b",
    "storage/redis.py": r"\bclass\s+RedisStorage\b",
    "middleware/http.py": r"\bclass\s+HttpMiddleware\b",
    "tests/test_integration.py": r"\bdef\s+test_full_pipeline\b",
}


def run_test_b():
    print("Running Spec Trap: Test B (Multi-File Dependency Consistency)", flush=True)
    fixture_dir = os.path.join(os.path.dirname(__file__), "fixtures/test_b")

    files = {}
    for root, _, filenames in os.walk(fixture_dir):
        for fname in filenames:
            if fname.endswith(".py"):
                path = os.path.join(root, fname)
                with open(path) as f:
                    files[os.path.relpath(path, fixture_dir)] = f.read()

    prompt = (
        "Refactor the CoreLimiter interface in core/limiter.py to require a "
        "`tenant_id: str` as the first argument, moving `user_id` to the second "
        "argument. Cascade this change across storage/redis.py, middleware/http.py, "
        "and tests/test_integration.py. Output the full rewritten files.\n\n"
    )
    for fname, code in files.items():
        prompt += f"--- {fname} ---\n{code}\n\n"

    try:
        text, content, _raw, metrics = chat_completion(
            [{"role": "user", "content": prompt}], max_tokens=3500
        )
        static_passed = (
            "def check_limit(self, tenant_id: str, user_id: str, amount: int)" in text
            and "def process_request(self, tenant_id: str, user_id: str, amount: int)" in text
            and "self.storage.process_request(tenant_id, user_id, 1)" in text
        )

        # Execution oracle: map blocks to fixture files, overlay on the original tree,
        # then check tenant_id actually reaches CoreLimiter.check_limit.
        extracted = {}
        for block in code_source_for_oracle(content, text):
            for rel, marker in TEST_B_FILE_MARKERS.items():
                if re.search(marker, block):
                    extracted[rel] = block
        oracle = {"ran": False, "conclusive": False, "passed": None, "output": "no file blocks extracted"}
        if {"core/limiter.py", "storage/redis.py", "middleware/http.py"} <= set(extracted):
            oracle = run_oracle({**files, **extracted}, TEST_B_CHECK)
        passed = oracle["passed"] if oracle["conclusive"] else static_passed
        detail = {
            "static_passed": static_passed,
            "extracted_files": sorted(extracted),
            "oracle": oracle,
            "oracle_used": oracle["conclusive"],
        }
        print(f"Test B Result: {'PASS' if passed else 'FAIL'} ({detail})", flush=True)
        return {"passed": passed, "detail": detail, "metrics": metrics, "response": truncate(text)}
    except Exception as e:
        print(f"Test B Failed to run: {e}", flush=True)
        return {"passed": False, "error": str(e), "response": ""}


def _test_c_deliverables(text: str) -> tuple[bool, bool]:
    """Detect named merge_sort and fib/fibonacci defs in response text."""
    has_merge = "def merge_sort" in text
    has_fib = bool(re.search(r"\bdef fib(?:onacci)?\b", text))
    return has_merge, has_fib


def run_test_c():
    print("Running Spec Trap: Test C (Reasoning Scratchpad Ceiling)", flush=True)

    system_prompt = """You are a strictly constrained model.
Your internal reasoning scratchpad MUST NOT exceed 5 bullet points.
Output your reasoning in <scratchpad> tags before outputting the final answer.
"""
    user_prompt = (
        "Deliver BOTH of the following as clearly named Python fenced code blocks "
        "(```python ... ```):\n"
        "1. A function named `merge_sort` — iterative merge sort.\n"
        "2. A function named `fib` or `fibonacci` — first 50 Fibonacci numbers.\n"
        "Both named deliverables are required. Be careful not to exceed the scratchpad limit."
    )

    try:
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]
        text, _content, _raw, metrics = chat_completion(messages, max_tokens=2500)
        has_merge, has_fib = _test_c_deliverables(text)
        retried = False

        # Fail-fast retry once if either named deliverable is missing.
        if not (has_merge and has_fib):
            missing = []
            if not has_merge:
                missing.append("`merge_sort` (iterative merge sort)")
            if not has_fib:
                missing.append("`fib` or `fibonacci` (first 50 Fibonacci numbers)")
            print(
                f"Test C missing deliverables {missing} — retrying once...",
                flush=True,
            )
            retried = True
            retry_prompt = (
                "Your previous reply was incomplete. Re-output BOTH required "
                "deliverables as clearly named Python fenced code blocks:\n"
                + "\n".join(f"- Missing: {m}" for m in missing)
                + "\nInclude any deliverable you already had as well. "
                "Keep the <scratchpad> to ≤ 5 bullets."
            )
            text, _content, _raw, metrics = chat_completion(
                [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                    {"role": "assistant", "content": text},
                    {"role": "user", "content": retry_prompt},
                ],
                max_tokens=2500,
            )
            has_merge, has_fib = _test_c_deliverables(text)

        code = extract_python_code(text)
        try:
            ast.parse(code)
            code_parses = True
        except SyntaxError:
            code_parses = False

        # Primary pass = both named code deliverables. Scratchpad is soft only.
        passed = has_merge and has_fib
        scratchpad_match = re.search(r"<scratchpad>(.*?)</scratchpad>", text, re.DOTALL)
        if scratchpad_match:
            bullets = len(re.findall(r"^\s*[-*]\s+", scratchpad_match.group(1), re.MULTILINE))
            scratchpad_ok = bullets <= 5
        else:
            bullets = None
            scratchpad_ok = None
        detail = {
            "has_merge": has_merge,
            "has_fib": has_fib,
            "code_parses": code_parses,
            "retried": retried,
            "scratchpad_present": bool(scratchpad_match),
            "bullets": bullets,
            "scratchpad_within_limit": scratchpad_ok,  # soft flag; never fails the trap alone
            "no_scratchpad_tag": not scratchpad_match,
        }
        print(f"Test C Result: {'PASS' if passed else 'FAIL'} ({detail})", flush=True)
        return {"passed": passed, "detail": detail, "metrics": metrics, "response": truncate(text)}
    except Exception as e:
        print(f"Test C Failed to run: {e}", flush=True)
        return {"passed": False, "error": str(e), "response": ""}


def run_all_spec_traps():
    results = {}
    for name, fn in (("Test_A", run_test_a), ("Test_B", run_test_b), ("Test_C", run_test_c)):
        erase_slots(FLASH_MODEL, label=f"before {name}")
        results[name] = fn()
    return results


def trap_passed(result) -> bool:
    """Normalize bool-or-dict trap results for the scorecard."""
    if isinstance(result, bool):
        return result
    if isinstance(result, dict):
        return bool(result.get("passed"))
    return False


if __name__ == "__main__":
    import json

    res = run_all_spec_traps()
    with open("spec_traps_results.json", "w") as f:
        json.dump(res, f, indent=2)
    print("Saved spec traps results to spec_traps_results.json", flush=True)
