#!/usr/bin/env bash
# =============================================================================
# hybrid-ai-harness / engine / bin/llama-up.sh
# Startup script for Workstation llama-server
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${ENGINE_DIR}/.." && pwd)"

# Source environment defaults
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
PREFLIGHT="${SCRIPT_DIR}/preflight.sh"
LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-/usr/bin/llama-server}"

RUN_DIR="${RUN_DIR:-${ENGINE_DIR}/run}"
LOG_DIR="${LOG_DIR:-${ENGINE_DIR}/run}"
PID_FILE="${RUN_DIR}/llama-server.pid"
LOG_FILE="${LOG_DIR}/llama-server.log"

MODE="single"
PRESET="${DEFAULT_PRESET}"
FOREGROUND=0
FORCE=0
SKIP_PREFLIGHT=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [MODE] [PRESET] [OPTIONS]

Start the Workstation llama-server local AI engine.

Modes:
    single [preset]    Run single model with preset CLI flags (default)
    router [preset]    Run router mode (--models-preset) and warm preset

Presets (from models.ini):
    qwen36-coder          Default: full 256k ctx, cpu-moe in DDR5 (20.6 GiB)
    qwen36-coder-hybrid   Candidate: n-cpu-moe 32 (8 expert layers in VRAM)
    glm47-reap            Alternative: 128k ctx, REAP-pruned 23B (14.1 GiB)

Options:
    -f, --foreground   Run in foreground (for systemd or interactive terminal)
    --port <port>      Listen port (default: ${PORT})
    --force            Bypass preflight hard failures
    --skip-preflight   Skip preflight checks entirely
    -h, --help         Show this help message
EOF
    exit 0
}

# Parse positional arguments and flags
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--foreground)
            FOREGROUND=1
            shift
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --skip-preflight)
            SKIP_PREFLIGHT=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL[@]} -ge 1 ]]; then
    case "${POSITIONAL[0]}" in
        single|router)
            MODE="${POSITIONAL[0]}"
            if [[ ${#POSITIONAL[@]} -ge 2 ]]; then
                PRESET="${POSITIONAL[1]}"
            fi
            ;;
        *)
            # Check if positional[0] is a preset name directly
            if python3 "${INI2ARGS}" "${MODELS_INI}" --list | grep -qx "${POSITIONAL[0]}"; then
                MODE="single"
                PRESET="${POSITIONAL[0]}"
            else
                echo "error: unrecognized mode or preset: ${POSITIONAL[0]}" >&2
                usage
            fi
            ;;
    esac
fi

# Ensure runtime directories exist
mkdir -p "${RUN_DIR}" "${LOG_DIR}"

# -----------------------------------------------------------------------------
# Preflight Verification
# -----------------------------------------------------------------------------
if [[ ${SKIP_PREFLIGHT} -eq 0 ]]; then
    PREFLIGHT_ARGS=(--preset "${PRESET}" --port "${PORT}")
    if [[ ${FORCE} -eq 1 ]]; then
        PREFLIGHT_ARGS+=(--force)
    fi
    if [[ ${FOREGROUND} -eq 1 ]]; then
        PREFLIGHT_ARGS+=(--quiet)
    fi

    if ! "${PREFLIGHT}" "${PREFLIGHT_ARGS[@]}"; then
        echo "error: preflight checks failed. Use --force to bypass or inspect issues above." >&2
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Construct Command
# -----------------------------------------------------------------------------
CMD=("${LLAMA_SERVER_BIN}")

if [[ "${MODE}" == "single" ]]; then
    # Flatten [*] + [<preset>] into array of CLI arguments
    mapfile -t PRESET_ARGS < <(python3 "${INI2ARGS}" "${MODELS_INI}" "${PRESET}")
    CMD+=("${PRESET_ARGS[@]}" "--port" "${PORT}")
elif [[ "${MODE}" == "router" ]]; then
    # Router mode: loads models on demand, capped at 1 model loaded at a time
    CMD+=(
        "--models-preset" "${MODELS_INI}"
        "--models-max" "1"
        "--host" "${HOST}"
        "--port" "${PORT}"
        "--metrics"
        "--slots"
    )
fi

# -----------------------------------------------------------------------------
# Foreground Execution (systemd or terminal)
# -----------------------------------------------------------------------------
if [[ ${FOREGROUND} -eq 1 ]]; then
    echo "Starting llama-server in foreground (mode: ${MODE}, preset: ${PRESET}, port: ${PORT})..."
    if [[ "${MODE}" == "router" ]]; then
        # In router mode with foreground, spawn background warmer
        (
            echo "Awaiting server health to warm preset '${PRESET}'..."
            for _ in $(seq 1 120); do
                if curl -s "http://${HOST}:${PORT}/health" 2>/dev/null | grep -q '"status":"ok"'; then
                    echo "Server healthy. Warming preset '${PRESET}' with 1-token ping..."
                    curl -s -X POST "http://${HOST}:${PORT}/v1/chat/completions" \
                        -H "Content-Type: application/json" \
                        -d "{\"model\": \"${PRESET}\", \"messages\": [{\"role\": \"user\", \"content\": \"ping\"}], \"max_tokens\": 1}" >/dev/null 2>&1 || true
                    echo "Warming request completed for '${PRESET}'."
                    break
                fi
                sleep 1
            done
        ) &
    fi
    exec "${CMD[@]}"
fi

# -----------------------------------------------------------------------------
# Background Execution (daemon)
# -----------------------------------------------------------------------------
# Check if already running via pidfile
if [[ -f "${PID_FILE}" ]]; then
    EXISTING_PID=$(cat "${PID_FILE}")
    if kill -0 "${EXISTING_PID}" 2>/dev/null; then
        echo "error: llama-server is already running with PID ${EXISTING_PID}." >&2
        echo "Use 'engine/bin/llama-down.sh' to stop it first." >&2
        exit 1
    else
        rm -f "${PID_FILE}"
    fi
fi

echo "Launching llama-server (mode: ${MODE}, preset: ${PRESET}, port: ${PORT})..."
echo "Command log: ${LOG_FILE}"

if command -v systemd-run >/dev/null 2>&1 && systemctl --user is-active basic.target >/dev/null 2>&1; then
    systemctl --user reset-failed berserker-llama-server 2>/dev/null || true
    systemd-run --user --unit=berserker-llama-server --collect \
        -p "WorkingDirectory=${REPO_DIR}" \
        -p "LimitMEMLOCK=infinity" \
        -p "StandardOutput=file:${LOG_FILE}" \
        -p "StandardError=file:${LOG_FILE}" \
        "${CMD[@]}" >/dev/null

    SERVER_PID=""
    for _ in $(seq 1 20); do
        SERVER_PID=$(systemctl --user show --property=MainPID berserker-llama-server 2>/dev/null | cut -d'=' -f2 || true)
        if [[ -n "${SERVER_PID}" && "${SERVER_PID}" =~ ^[0-9]+$ && "${SERVER_PID}" -gt 0 ]]; then
            break
        fi
        sleep 0.2
    done
    if [[ -z "${SERVER_PID}" || "${SERVER_PID}" -eq 0 ]]; then
        echo "error: failed to obtain PID from systemd-run unit." >&2
        exit 1
    fi
else
    "${CMD[@]}" > "${LOG_FILE}" 2>&1 &
    SERVER_PID=$!
fi

echo "${SERVER_PID}" > "${PID_FILE}"

echo "Spawned process PID ${SERVER_PID}. Waiting for /health..."

HEALTH_TIMEOUT=120
HEALTHY=0
for ((i=1; i<=HEALTH_TIMEOUT; i++)); do
    # Check if process is still alive
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
        echo "error: llama-server process ${SERVER_PID} terminated unexpectedly during startup." >&2
        echo "--- Last 25 lines of ${LOG_FILE} ---" >&2
        tail -n 25 "${LOG_FILE}" >&2
        rm -f "${PID_FILE}"
        exit 1
    fi

    # Poll /health endpoint
    HEALTH_RESP=$(curl -s "http://${HOST}:${PORT}/health" 2>/dev/null || true)
    if [[ "${HEALTH_RESP}" == *'"status":"ok"'* ]]; then
        HEALTHY=1
        break
    fi

    if (( i % 5 == 0 )); then
        echo "  [${i}s / ${HEALTH_TIMEOUT}s] Loading model weights into RAM/VRAM..."
    fi
    sleep 1
done

if [[ ${HEALTHY} -eq 0 ]]; then
    echo "error: timed out waiting for http://${HOST}:${PORT}/health after ${HEALTH_TIMEOUT}s." >&2
    echo "--- Last 25 lines of ${LOG_FILE} ---" >&2
    tail -n 25 "${LOG_FILE}" >&2
    exit 1
fi

echo "llama-server is HEALTHY on port ${PORT} (PID ${SERVER_PID})."

if [[ "${MODE}" == "router" ]]; then
    echo "Warming router preset '${PRESET}' with 1-token prompt..."
    WARM_START=$(date +%s)
    WARM_RESP=$(curl -s -X POST "http://${HOST}:${PORT}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"${PRESET}\", \"messages\": [{\"role\": \"user\", \"content\": \"ping\"}], \"max_tokens\": 1}" || true)
    WARM_END=$(date +%s)
    WARM_DUR=$((WARM_END - WARM_START))
    echo "Warm request complete in ${WARM_DUR}s."
fi

echo ""
echo "=== Engine Ready ==="
echo "  Mode:     ${MODE}"
echo "  Preset:   ${PRESET}"
echo "  Endpoint: http://${HOST}:${PORT}/v1"
echo "  PID:      ${SERVER_PID}"
echo "  Log:      ${LOG_FILE}"
