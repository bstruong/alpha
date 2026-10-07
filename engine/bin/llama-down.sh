#!/usr/bin/env bash
# =============================================================================
# hybrid-ai-harness / engine / bin/llama-down.sh
# Graceful shutdown script for Workstation llama-server
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source environment defaults
ENV_FILE="${ENGINE_DIR}/workstation.env"
if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
fi

PORT="${PORT:-8080}"
RUN_DIR="${RUN_DIR:-${ENGINE_DIR}/run}"
PID_FILE="${RUN_DIR}/llama-server.pid"
FORCE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Stop the Workstation llama-server local AI engine.

Options:
    --port <port>   Port to inspect if pidfile is missing (default: ${PORT})
    --force         Kill matching process on port even without pidfile
    -h, --help      Show this help message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)
            PORT="$2"
            shift 2
            ;;
        --force)
            FORCE=1
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

stop_pid() {
    local pid="$1"
    local name="${2:-llama-server}"

    if ! kill -0 "${pid}" 2>/dev/null; then
        echo "Process ${pid} is not running."
        return 0
    fi

    echo "Stopping ${name} (PID ${pid})..."
    kill -TERM "${pid}" 2>/dev/null || true

    # Wait up to 15 seconds for clean exit
    local stopped=0
    for _ in $(seq 1 30); do
        if ! kill -0 "${pid}" 2>/dev/null; then
            stopped=1
            break
        fi
        sleep 0.5
    done

    if [[ ${stopped} -eq 0 ]]; then
        echo "Process ${pid} did not exit after 15s. Sending SIGKILL..."
        kill -KILL "${pid}" 2>/dev/null || true
        sleep 0.5
    fi

    echo "Process ${pid} stopped."
}

# 0. Check systemd units
if command -v systemctl >/dev/null 2>&1; then
    for unit in berserker-llama-server.service berserker-llama.service; do
        if systemctl --user is-active --quiet "${unit}" 2>/dev/null; then
            echo "Stopping systemd unit ${unit}..."
            systemctl --user stop "${unit}" 2>/dev/null || true
        fi
    done
fi

# 1. Check PID file
if [[ -f "${PID_FILE}" ]]; then
    TARGET_PID=$(cat "${PID_FILE}")
    if [[ -n "${TARGET_PID}" && "${TARGET_PID}" =~ ^[0-9]+$ ]]; then
        if kill -0 "${TARGET_PID}" 2>/dev/null; then
            stop_pid "${TARGET_PID}" "llama-server"
            rm -f "${PID_FILE}"
            exit 0
        else
            echo "Removing stale pidfile: ${PID_FILE} (PID ${TARGET_PID} not running)."
            rm -f "${PID_FILE}"
        fi
    else
        rm -f "${PID_FILE}"
    fi
fi

# 2. Check if a process is listening on the port
PORT_PID=""
PORT_CMD=""
if command -v ss >/dev/null 2>&1; then
    PORT_LINE=$(ss -tulpn "sport = :${PORT}" 2>/dev/null | grep -E ":${PORT}\b" | head -n 1 || true)
    if [[ -n "${PORT_LINE}" ]]; then
        PORT_PID=$(echo "${PORT_LINE}" | grep -o 'pid=[0-9]*' | cut -d'=' -f2 | head -n 1 || true)
        PORT_CMD=$(echo "${PORT_LINE}" | grep -o 'users:(("[^"]*"' | cut -d'"' -f2 || true)
    fi
elif command -v lsof >/dev/null 2>&1; then
    PORT_LINE=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | tail -n +2 | head -n 1 || true)
    if [[ -n "${PORT_LINE}" ]]; then
        PORT_PID=$(echo "${PORT_LINE}" | awk '{print $2}')
        PORT_CMD=$(echo "${PORT_LINE}" | awk '{print $1}')
    fi
fi

if [[ -n "${PORT_PID}" ]]; then
    echo "Found process ${PORT_PID} (${PORT_CMD}) listening on port ${PORT} without a pidfile."
    if [[ "${PORT_CMD}" == *"llama-server"* ]]; then
        if [[ ${FORCE} -eq 1 ]]; then
            stop_pid "${PORT_PID}" "llama-server"
            exit 0
        else
            echo "Pass --force to stop PID ${PORT_PID} (${PORT_CMD})."
            exit 1
        fi
    else
        echo "Process is not llama-server (${PORT_CMD}). Refusing to terminate."
        exit 1
    fi
fi

echo "No running llama-server found (pidfile missing and port ${PORT} inactive)."
exit 0
