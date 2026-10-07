#!/usr/bin/env bash
# =============================================================================
# hybrid-ai-harness / engine / bin/preflight.sh
# Preflight environment and hardware check for Workstation llama-server
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${ENGINE_DIR}/.." && pwd)"

# Source environment defaults if available
ENV_FILE="${ENGINE_DIR}/workstation.env"
if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
fi

PORT="${PORT:-8080}"
HOST="${HOST:-127.0.0.1}"
DEFAULT_PRESET="${DEFAULT_PRESET:-qwen36-coder}"
MODELS_INI="${MODELS_INI:-${ENGINE_DIR}/models.ini}"
INI2ARGS="${SCRIPT_DIR}/ini2args.py"

PRESET="${DEFAULT_PRESET}"
FORCE=0
QUIET=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Preflight check for Workstation llama-server execution environment.
Checks memlock limits, CPU RAM, GPU VRAM, port availability, model files,
and Ollama status.

Options:
    --preset <name>   Preset to check from models.ini (default: ${DEFAULT_PRESET})
    --port <port>     Port to verify (default: ${PORT})
    --force           Return success even if hard checks fail
    --quiet           Suppress non-error output
    -h, --help        Show this help message

Exit codes:
    0 = All checks passed or warnings only (or --force used)
    1 = Hard check failure (insufficient memory, missing model, port collision)
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --preset)
            PRESET="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --quiet)
            QUIET=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

ERRORS=0
WARNINGS=0

log_info() {
    if [[ ${QUIET} -eq 0 ]]; then
        echo -e "[INFO]  $*"
    fi
}

log_ok() {
    if [[ ${QUIET} -eq 0 ]]; then
        echo -e "\033[0;32m[OK]\033[0m    $*"
    fi
}

log_warn() {
    echo -e "\033[1;33m[WARN]\033[0m  $*"
    WARNINGS=$((WARNINGS + 1))
}

log_fail() {
    echo -e "\033[0;31m[FAIL]\033[0m  $*"
    ERRORS=$((ERRORS + 1))
}

log_header() {
    if [[ ${QUIET} -eq 0 ]]; then
        echo ""
        echo "=== $* ==="
    fi
}

log_header "Workstation Preflight Check (Preset: ${PRESET})"

# -----------------------------------------------------------------------------
# 1. Preset & Model Validation
# -----------------------------------------------------------------------------
if [[ ! -f "${MODELS_INI}" ]]; then
    log_fail "models.ini not found at: ${MODELS_INI}"
else
    if ! python3 "${INI2ARGS}" "${MODELS_INI}" --list | grep -qx "${PRESET}"; then
        log_fail "Preset '[${PRESET}]' not found in ${MODELS_INI}"
    else
        MODEL_PATH=$(python3 "${INI2ARGS}" "${MODELS_INI}" "${PRESET}" --get model || true)
        if [[ -z "${MODEL_PATH}" ]]; then
            log_fail "Preset '[${PRESET}]' does not specify a 'model' key"
        elif [[ ! -f "${MODEL_PATH}" ]]; then
            log_fail "Model file not found: ${MODEL_PATH}"
        else
            MODEL_SIZE_BYTES=$(stat -c%s "${MODEL_PATH}" 2>/dev/null || stat -f%z "${MODEL_PATH}")
            MODEL_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", ${MODEL_SIZE_BYTES}/(1024^3)}")
            log_ok "Model file exists: ${MODEL_PATH} (${MODEL_SIZE_GB} GiB)"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# 2. Driver, CUDA, and GPU VRAM
# -----------------------------------------------------------------------------
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,memory.free,memory.used,driver_version --format=csv,noheader,nounits 2>/dev/null | head -n 1 || true)
    if [[ -n "${GPU_INFO}" ]]; then
        IFS=',' read -r GPU_NAME GPU_TOTAL_MIB GPU_FREE_MIB GPU_USED_MIB DRV_VER <<< "${GPU_INFO}"
        GPU_NAME=$(echo "${GPU_NAME}" | xargs)
        GPU_TOTAL_MIB=$(echo "${GPU_TOTAL_MIB}" | xargs)
        GPU_FREE_MIB=$(echo "${GPU_FREE_MIB}" | xargs)
        GPU_USED_MIB=$(echo "${GPU_USED_MIB}" | xargs)
        DRV_VER=$(echo "${DRV_VER}" | xargs)

        CUDA_VER="unknown"
        if command -v nvcc >/dev/null 2>&1; then
            CUDA_VER=$(nvcc --version | grep -o 'release [0-9.]*' | awk '{print $2}' || true)
        fi
        log_ok "GPU: ${GPU_NAME} | Driver: ${DRV_VER} | CUDA: ${CUDA_VER} | VRAM: ${GPU_USED_MIB}/${GPU_TOTAL_MIB} MiB used"

        # Check VRAM requirement for the preset
        # qwen36-coder: ~6.3 GB VRAM (weights + q8_0 KV + headroom)
        # qwen36-coder-hybrid (n-cpu-moe 32): ~10.2 GB VRAM
        REQUIRED_VRAM_MIB=6400
        if [[ "${PRESET}" == *"hybrid"* ]]; then
            REQUIRED_VRAM_MIB=10400
        fi

        if [[ ${GPU_FREE_MIB} -lt ${REQUIRED_VRAM_MIB} ]]; then
            # Check if existing llama-server is currently using the VRAM
            if pgrep -f "llama-server" >/dev/null 2>&1; then
                LLAMA_PIDS=$(pgrep -d',' -f "llama-server" || true)
                log_warn "Free VRAM (${GPU_FREE_MIB} MiB) is below target ${REQUIRED_VRAM_MIB} MiB, but running llama-server (PID ${LLAMA_PIDS}) currently holds VRAM. Stopping it will free ~8.5 GiB."
            else
                log_warn "Free VRAM (${GPU_FREE_MIB} MiB) is below recommended ${REQUIRED_VRAM_MIB} MiB. Another process may be using the GPU."
            fi
        else
            log_ok "Free VRAM is sufficient: ${GPU_FREE_MIB} MiB free (target: ${REQUIRED_VRAM_MIB} MiB)"
        fi
    else
        log_warn "nvidia-smi returned empty GPU info."
    fi
else
    log_warn "nvidia-smi command not found. Cannot verify GPU VRAM."
fi

# -----------------------------------------------------------------------------
# 3. Memory Lock Limit (RLIMIT_MEMLOCK / ulimit -l)
# -----------------------------------------------------------------------------
MEMLOCK_KB=$(ulimit -l 2>/dev/null || echo "0")
if [[ "${MEMLOCK_KB}" == "unlimited" ]]; then
    log_ok "RLIMIT_MEMLOCK is unlimited (mlock supported)"
else
    # Convert model size to KB
    if [[ -n "${MODEL_SIZE_BYTES:-}" ]]; then
        MODEL_SIZE_KB=$((MODEL_SIZE_BYTES / 1024))
        if [[ ${MEMLOCK_KB} -lt ${MODEL_SIZE_KB} ]]; then
            log_warn "RLIMIT_MEMLOCK is ${MEMLOCK_KB} KB (< ${MODEL_SIZE_KB} KB needed for ${PRESET})."
            echo "         --load-mode mlock will fail silently; pages will not be locked into RAM (VmLck=0)."
            echo "         To fix: run 'engine/bin/setup-memlock.sh' or install 'engine/system/90-berserker-memlock.conf'."
        else
            log_ok "RLIMIT_MEMLOCK is sufficient: ${MEMLOCK_KB} KB"
        fi
    else
        if [[ ${MEMLOCK_KB} -lt 16777216 ]]; then # 16 GB in KB
            log_warn "RLIMIT_MEMLOCK is ${MEMLOCK_KB} KB. --load-mode mlock will fail silently without elevated limits."
        fi
    fi
fi

# -----------------------------------------------------------------------------
# 4. CPU RAM Availability (MemAvailable vs. CPU footprint)
# -----------------------------------------------------------------------------
if [[ -f "/proc/meminfo" ]]; then
    MEM_AVAIL_KB=$(grep -i "MemAvailable:" /proc/meminfo | awk '{print $2}')
    MEM_AVAIL_GB=$(awk "BEGIN {printf \"%.2f\", ${MEM_AVAIL_KB}/(1024^2)}")

    # Estimate CPU memory footprint in GiB
    # Formula:
    #   qwen36-coder: file size (20.61 GiB) - ~2.6 GiB (GPU) + ~2 GiB (cache-ram) ≈ 20.0 GiB
    #   qwen36-coder-hybrid: 20.61 GiB - ~2.6 GiB - ~3.9 GiB (8 expert layers) + 2 GiB ≈ 16.1 GiB
    #   glm47-reap: file size (14.1 GiB) - ~1.1 GiB + 2 GiB ≈ 15.0 GiB
    EST_CPU_GB="20.50"
    if [[ "${PRESET}" == *"hybrid"* ]]; then
        EST_CPU_GB="17.60"
    elif [[ "${PRESET}" == *"glm"* ]]; then
        EST_CPU_GB="15.00"
    fi

    # Convert EST_CPU_GB to KB
    EST_CPU_KB=$(awk "BEGIN {printf \"%d\", ${EST_CPU_GB} * 1024 * 1024}")

    if [[ ${MEM_AVAIL_KB} -lt ${EST_CPU_KB} ]]; then
        if pgrep -f "llama-server" >/dev/null 2>&1; then
            LLAMA_PIDS=$(pgrep -d',' -f "llama-server" || true)
            log_warn "MemAvailable is ${MEM_AVAIL_GB} GiB (< estimated ${EST_CPU_GB} GiB needed for ${PRESET}), but running llama-server (PID ${LLAMA_PIDS}) currently occupies ~19.5 GiB of host RAM. Stopping it will free sufficient memory."
        else
            log_fail "MemAvailable is only ${MEM_AVAIL_GB} GiB, but preset requires approximately ${EST_CPU_GB} GiB of CPU RAM. High risk of OOM or severe swap thrashing."
        fi
    else
        log_ok "MemAvailable is sufficient: ${MEM_AVAIL_GB} GiB available (estimated requirement: ${EST_CPU_GB} GiB)"
    fi
else
    log_warn "/proc/meminfo not accessible; skipping RAM availability check."
fi

# -----------------------------------------------------------------------------
# 5. Port Availability
# -----------------------------------------------------------------------------
PORT_IN_USE=0
PORT_PID=""
PORT_CMD=""

if command -v ss >/dev/null 2>&1; then
    PORT_LINE=$(ss -tulpn "sport = :${PORT}" 2>/dev/null | grep -E ":${PORT}\b" | head -n 1 || true)
    if [[ -n "${PORT_LINE}" ]]; then
        PORT_IN_USE=1
        PORT_PID=$(echo "${PORT_LINE}" | grep -o 'pid=[0-9]*' | cut -d'=' -f2 | head -n 1 || true)
        PORT_CMD=$(echo "${PORT_LINE}" | grep -o 'users:(("[^"]*"' | cut -d'"' -f2 || true)
    fi
elif command -v lsof >/dev/null 2>&1; then
    PORT_LINE=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | tail -n +2 | head -n 1 || true)
    if [[ -n "${PORT_LINE}" ]]; then
        PORT_IN_USE=1
        PORT_PID=$(echo "${PORT_LINE}" | awk '{print $2}')
        PORT_CMD=$(echo "${PORT_LINE}" | awk '{print $1}')
    fi
fi

if [[ ${PORT_IN_USE} -eq 1 ]]; then
    if [[ -n "${PORT_PID}" && "${PORT_CMD}" == *"llama-server"* ]]; then
        log_fail "Port ${PORT} is currently in use by llama-server (PID ${PORT_PID}). Stop it before starting a new server."
    elif [[ -n "${PORT_PID}" ]]; then
        log_fail "Port ${PORT} is occupied by PID ${PORT_PID} (${PORT_CMD})."
    else
        log_fail "Port ${PORT} is already in use by another process."
    fi
else
    log_ok "Port ${PORT} is free."
fi

# -----------------------------------------------------------------------------
# 6. Ollama Status Check
# -----------------------------------------------------------------------------
OLLAMA_PORT="11434"
OLLAMA_RESP=$(curl -s --max-time 2 "http://127.0.0.1:${OLLAMA_PORT}/api/ps" 2>/dev/null || true)

if [[ -n "${OLLAMA_RESP}" ]]; then
    # Parse models from JSON response
    LOADED_COUNT=$(python3 -c "import sys, json; data=json.loads(sys.argv[1]); print(len(data.get('models', [])))" "${OLLAMA_RESP}" 2>/dev/null || echo "0")
    if [[ "${LOADED_COUNT}" -gt 0 ]]; then
        MODEL_NAMES=$(python3 -c "import sys, json; data=json.loads(sys.argv[1]); print(', '.join(m.get('name', 'unknown') for m in data.get('models', [])))" "${OLLAMA_RESP}" 2>/dev/null || echo "models")
        log_warn "Ollama is active on :${OLLAMA_PORT} with loaded model(s): ${MODEL_NAMES}. This creates VRAM and DDR5 contention. Run 'systemctl stop ollama' or stop the model before running benchmarks."
    else
        log_ok "Ollama is listening on :${OLLAMA_PORT} but has no models loaded (idle)."
    fi
else
    log_ok "Ollama is not running (port ${OLLAMA_PORT} inactive)."
fi

# -----------------------------------------------------------------------------
# 7. Summary & Exit Verdict
# -----------------------------------------------------------------------------
log_header "Verdict"
if [[ ${ERRORS} -eq 0 && ${WARNINGS} -eq 0 ]]; then
    echo -e "\033[0;32mPreflight PASSED with no warnings.\033[0m Ready to launch preset '${PRESET}'."
    exit 0
elif [[ ${ERRORS} -eq 0 ]]; then
    echo -e "\033[1;33mPreflight PASSED with ${WARNINGS} warning(s).\033[0m Review warnings above before launching."
    exit 0
else
    if [[ ${FORCE} -eq 1 ]]; then
        echo -e "\033[1;33mPreflight encountered ${ERRORS} error(s) and ${WARNINGS} warning(s), but --force was specified. Proceeding.\033[0m"
        exit 0
    else
        echo -e "\033[0;31mPreflight FAILED with ${ERRORS} error(s) and ${WARNINGS} warning(s).\033[0m Resolve errors or pass --force to bypass."
        exit 1
    fi
fi
