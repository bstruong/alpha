import os
import time
import subprocess
import json
import re

def run_benchmark():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    trap_dir = os.path.join(base_dir, 'tests', 'spec_trap')
    reports_dir = os.path.join(base_dir, 'reports')
    engine_log = os.path.join(base_dir, 'engine', 'run', 'llama-server.log')
    
    os.makedirs(reports_dir, exist_ok=True)
    pi_log_file = os.path.join(reports_dir, 'pi_benchmark.log')
    
    with open(os.path.join(trap_dir, 'ARCH_SPEC.md'), 'r') as f: arch_spec = f.read()
    with open(os.path.join(trap_dir, 'test_rate_limiter.py'), 'r') as f: test_code = f.read()
    with open(os.path.join(trap_dir, 'legacy_limiter.py'), 'r') as f: legacy_code = f.read()
    
    prompt = f"""Fix the failing tests while fully adhering to the architectural spec.
Implement the missing `rate_limiter.py` in the `tests/spec_trap` directory. Ensure `test_rate_limiter.py` is fixed to not use float.

### ARCH_SPEC.md
{arch_spec}

### test_rate_limiter.py
{test_code}

### legacy_limiter.py
{legacy_code}
"""

    # Truncate the engine log so the harness starts with a clean slate
    try:
        with open(engine_log, 'w'):
            pass
        print(f"[benchmark] Truncated {engine_log}")
    except OSError:
        pass  # Log may not exist yet; that's fine

    print("Running Pi harness with the benchmark prompt...")
    env = os.environ.copy()
    env["PI_LOG_FILE"] = pi_log_file
    
    # Clear log to prevent stale metric scraping
    if os.path.exists(engine_log):
        open(engine_log, 'w').close()
    
    cmd = [
        os.path.join(base_dir, 'harness', 'pi', 'bin', 'pi-monitored.sh'),
        "--provider", "openai-compatible",
        "--model", "qwen3.8-flash",
        "-p", prompt
    ]
    
    start_time = time.time()
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    end_time = time.time()
    
    print(f"Harness execution completed in {end_time - start_time:.2f} seconds.")
    
    prefill_speed = 0.0
    decode_speed = 0.0
    ttft = 0.0
    
    if os.path.exists(engine_log):
        with open(engine_log, 'r', errors='ignore') as f:
            new_logs = f.read()
            
            prompt_evals = re.findall(r'prompt eval time =.*?ms /.*?tokens .*? ([\d.]+) tokens per second', new_logs)
            evals = re.findall(r'eval time =.*?ms /.*?tokens .*? ([\d.]+) tokens per second', new_logs)
            ttfts = re.findall(r'prompt eval time =.*?([\d.]+) ms', new_logs)
            
            if prompt_evals: prefill_speed = float(prompt_evals[-1])
            if evals: decode_speed = float(evals[-1])
            if ttfts: ttft = float(ttfts[-1]) / 1000.0
                
    scratchpad_tokens = 0
    full_content = ""
    if os.path.exists(pi_log_file):
        with open(pi_log_file, 'r', errors='ignore') as f:
            full_content = f.read()
            
        think_match = re.search(r'<think>(.*?)</think>', full_content, re.DOTALL)
        if think_match:
            reasoning = think_match.group(1)
            scratchpad_tokens = int(len(reasoning.split()) * 1.3)
    else:
        full_content = result.stdout
        
    rate_limiter_path = os.path.join(trap_dir, 'rate_limiter.py')
    test_limiter_path = os.path.join(trap_dir, 'test_rate_limiter.py')
    
    written_code = ""
    if os.path.exists(rate_limiter_path):
        with open(rate_limiter_path, 'r') as f: written_code += f.read()
        
    if os.path.exists(test_limiter_path):
        with open(test_limiter_path, 'r') as f: written_code += f.read()
        
    if not written_code:
        written_code = full_content
        
    pass_decimal_maintenance = "FAIL"
    pass_spec_resolution = "FAIL"
    
    # We strip 'legacy_limiter.py' out of full_content to avoid false positives if we fallback
    content_to_check = written_code if written_code != full_content else full_content.replace(legacy_code, "")
    
    if "Decimal" in content_to_check and "float(" not in content_to_check:
        pass_decimal_maintenance = "PASS"
        
    if "float(" not in content_to_check:
        pass_spec_resolution = "PASS"

    metrics = {
        "Prefill Speed (t/s)": prefill_speed,
        "TTFT (s)": ttft,
        "Decode Speed (t/s)": decode_speed,
        "Scratchpad Token Count": scratchpad_tokens,
        "Spec vs. Flawed Test Resolution": pass_spec_resolution,
        "Decimal Precision Maintenance": pass_decimal_maintenance
    }

    report_path = os.path.join(reports_dir, 'frontier_spec_trap_results.json')
    with open(report_path, 'w') as f:
        json.dump(metrics, f, indent=2)

    print("\n" + "="*50)
    print("BENCHMARK SCORECARD")
    print("="*50)
    print(f"Prefill Speed: {metrics['Prefill Speed (t/s)']} t/s")
    print(f"TTFT:          {metrics['TTFT (s)']} s")
    print(f"Decode Speed:  {metrics['Decode Speed (t/s)']} t/s")
    print(f"Scratchpad Tokens: ~{metrics['Scratchpad Token Count']}")
    print(f"Spec Resolution: {metrics['Spec vs. Flawed Test Resolution']}")
    print(f"Decimal Precision: {metrics['Decimal Precision Maintenance']}")
    print("="*50)

if __name__ == '__main__':
    run_benchmark()
