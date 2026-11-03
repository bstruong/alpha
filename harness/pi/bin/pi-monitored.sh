#!/usr/bin/env bash
# =============================================================================
# hybrid-ai-harness / harness / pi / bin / pi-monitored.sh
# Monitored runner for Pi Local Harness with engine lifecycle management
# =============================================================================
set -e
set -o pipefail

# Directory and script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ENGINE_DIR="${REPO_DIR}/engine"

LLAMA_UP="${ENGINE_DIR}/bin/llama-up.sh"
LLAMA_DOWN="${ENGINE_DIR}/bin/llama-down.sh"
PID_FILE="${ENGINE_DIR}/run/llama-server.pid"
PI_UP="${SCRIPT_DIR}/pi-up.sh"

# Fallback relative resolution if paths differ
if [[ ! -x "${LLAMA_UP}" && -x "${SCRIPT_DIR}/../../engine/bin/llama-up.sh" ]]; then
    LLAMA_UP="${SCRIPT_DIR}/../../engine/bin/llama-up.sh"
    LLAMA_DOWN="${SCRIPT_DIR}/../../engine/bin/llama-down.sh"
fi

LLAMA_SERVER_URL="${LLAMA_SERVER_URL:-http://127.0.0.1:8080}"
LLAMA_HEALTH_URL="${LLAMA_SERVER_URL}/health"

# -----------------------------------------------------------------------------
# Model-to-Presets Mapping
# -----------------------------------------------------------------------------
# Extract the model name from --model <name> argument and build the preset.
extract_model_preset() {
    local preset="router qwen36-coder"  # legacy fallback
    local i=1
    while [[ $i -lt $# ]]; do
        if [[ "${!i}" == "--model" ]]; then
            local model="${!((i+1))}"
            preset="router ${model}"
            break
        fi
        ((i++))
    done
    echo "${preset}"
}

# -----------------------------------------------------------------------------
# Lifecycle Cleanup & Traps
# -----------------------------------------------------------------------------
cleanup() {
    local exit_code="${1:-$?}"
    # Unarm traps to avoid re-entrant calls
    trap - EXIT INT TERM HUP

    # Remote inference host or explicit persist flag: do not shut down remote engine
    if [[ "${LLAMA_SERVER_URL}" != *"127.0.0.1"* && "${LLAMA_SERVER_URL}" != *"localhost"* ]]; then
        : # Remote server, keep running on host
    elif [[ "${ALPHA_PERSIST_ENGINE:-0}" == "1" || "${PERSIST_ENGINE:-0}" == "1" ]]; then
        echo "[pi-monitored] PERSIST_ENGINE is enabled; skipping engine shutdown."
    else
        echo "[pi-monitored] Gracefully flushing engine weights from system RAM..."
        if [[ -x "${LLAMA_DOWN}" ]]; then
            "${LLAMA_DOWN}" || true
        fi
    fi
    exit "${exit_code}"
}


on_signal() {
    local sig="$1"
    local code="$2"
    echo "[pi-monitored] Interrupted by SIG${sig}."
    cleanup "${code}"
}

# Arm traps immediately to ensure cleanup on unexpected interrupt during startup
trap cleanup EXIT
trap "on_signal INT 130" INT
trap "on_signal TERM 143" TERM
trap "on_signal HUP 129" HUP

# -----------------------------------------------------------------------------
# Engine Status Check & Startup
# -----------------------------------------------------------------------------
is_llama_active() {
    # 1. Check health endpoint directly
    local health_resp
    health_resp=$(curl -s -m 2 "${LLAMA_HEALTH_URL}" 2>/dev/null || true)
    if [[ "${health_resp}" == *'"status":"ok"'* || "${health_resp}" == *'"status": "ok"'* ]]; then
        return 0
    fi

    # 2. Check PID file
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
            return 0
        fi
    fi

    # 3. Check systemd unit
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl --user is-active --quiet alpha-llama-server 2>/dev/null || \
           systemctl --user is-active --quiet alpha-llama.service 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

ensure_engine_ready() {
    if is_llama_active; then
        echo "[pi-monitored] llama-server is active."
        # If active by pid/systemd but health endpoint is not yet ready, wait
        local health_resp
        health_resp=$(curl -s -m 2 "${LLAMA_HEALTH_URL}" 2>/dev/null || true)
        if [[ "${health_resp}" != *'"status":"ok"'* && "${health_resp}" != *'"status": "ok"'* ]]; then
            echo "[pi-monitored] Waiting for llama-server to become healthy at ${LLAMA_HEALTH_URL}..."
            local health_timeout=120
            local healthy=0
            for ((i=1; i<=health_timeout; i++)); do
                health_resp=$(curl -s -m 2 "${LLAMA_HEALTH_URL}" 2>/dev/null || true)
                if [[ "${health_resp}" == *'"status":"ok"'* || "${health_resp}" == *'"status": "ok"'* ]]; then
                    healthy=1
                    break
                fi
                sleep 1
            done
            if [[ ${healthy} -eq 0 ]]; then
                echo "[pi-monitored] Error: Timed out waiting for llama-server at ${LLAMA_HEALTH_URL}." >&2
                exit 1
            fi
        fi
    else
        if [[ "${LLAMA_SERVER_URL}" != *"127.0.0.1"* && "${LLAMA_SERVER_URL}" != *"localhost"* ]]; then
            echo "[pi-monitored] Error: Remote llama-server is not reachable at ${LLAMA_SERVER_URL}." >&2
            echo "[pi-monitored] Please verify llama-server / alpha-llama.service on your inference host" >&2
            exit 1
        fi
        local model_preset
        model_preset=$(extract_model_preset "$@")
        echo "[pi-monitored] llama-server is not running. Spinning up ${model_preset}..."
        if [[ ! -x "${LLAMA_UP}" ]]; then
            echo "[pi-monitored] Error: llama-up script not found or executable at ${LLAMA_UP}." >&2
            exit 1
        fi
        "${LLAMA_UP}" ${model_preset}
    fi
}

if [[ "${ALPHA_SKIP_ENGINE:-0}" != "1" && "${SKIP_ENGINE:-0}" != "1" ]]; then
    ensure_engine_ready "$@"
fi


# -----------------------------------------------------------------------------
# Execute Monitored Harness
# -----------------------------------------------------------------------------
if [[ ! -x "${PI_UP}" ]]; then
    echo "[pi-monitored] Error: pi-up script not found at ${PI_UP}." >&2
    exit 1
fi

"${PI_UP}" "$@"
EXIT_STATUS=$?
exit "${EXIT_STATUS}"
