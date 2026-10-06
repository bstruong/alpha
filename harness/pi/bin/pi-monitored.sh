#!/usr/bin/env bash
# =============================================================================
# berserker / harness / pi / bin / pi-monitored.sh
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
# Lifecycle Cleanup & Traps
# -----------------------------------------------------------------------------
cleanup() {
    local exit_code="${1:-$?}"
    # Unarm traps to avoid re-entrant calls
    trap - EXIT INT TERM HUP

    if [[ "${BERSERKER_PERSIST_ENGINE:-0}" == "1" || "${PERSIST_ENGINE:-0}" == "1" ]]; then
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
        if systemctl --user is-active --quiet berserker-llama-server 2>/dev/null || \
           systemctl --user is-active --quiet berserker-llama.service 2>/dev/null; then
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
        echo "[pi-monitored] llama-server is not running. Spinning up single qwen36-coder..."
        if [[ ! -x "${LLAMA_UP}" ]]; then
            echo "[pi-monitored] Error: llama-up script not found or executable at ${LLAMA_UP}." >&2
            exit 1
        fi
        "${LLAMA_UP}" single qwen36-coder
    fi
}

if [[ "${BERSERKER_SKIP_ENGINE:-0}" != "1" && "${SKIP_ENGINE:-0}" != "1" ]]; then
    ensure_engine_ready
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
