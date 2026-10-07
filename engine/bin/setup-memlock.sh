#!/usr/bin/env bash
# =============================================================================
# berserker / engine / bin/setup-memlock.sh
# Diagnostic and helper tool for Metrotower RLIMIT_MEMLOCK configuration
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SYSTEM_DIR="${ENGINE_DIR}/system"

PAM_SRC="${SYSTEM_DIR}/90-berserker-memlock.conf"
PAM_DST="/etc/security/limits.d/90-berserker-memlock.conf"

SYSTEMD_DROPIN_DIR="/etc/systemd/system/user@.service.d"
SYSTEMD_SRC="${SYSTEM_DIR}/user@.service.d/memlock.conf"
SYSTEMD_DST="${SYSTEMD_DROPIN_DIR}/memlock.conf"

check_status() {
    echo "=== Metrotower RLIMIT_MEMLOCK Status ==="
    echo ""

    # Current shell limit
    CUR_SHELL_LIMIT=$(ulimit -l 2>/dev/null || echo "unknown")
    echo -n "1. Current Shell limit (ulimit -l): "
    if [[ "${CUR_SHELL_LIMIT}" == "unlimited" ]]; then
        echo -e "\033[0;32munlimited (OK)\033[0m"
    else
        echo -e "\033[1;33m${CUR_SHELL_LIMIT} KB (LIMITED)\033[0m"
        echo "   -> llama-server --load-mode mlock cannot lock model weights into RAM."
    fi

    # Systemd user manager limit
    USER_SYSTEMD_LIMIT=$(systemctl --user show -p DefaultLimitMEMLOCK 2>/dev/null | cut -d'=' -f2 || echo "unknown")
    echo -n "2. Systemd User Manager limit: "
    if [[ "${USER_SYSTEMD_LIMIT}" == "infinity" || "${USER_SYSTEMD_LIMIT}" == "18446744073709551615" ]]; then
        echo -e "\033[0;32m${USER_SYSTEMD_LIMIT} (OK)\033[0m"
    else
        echo -e "\033[1;33m${USER_SYSTEMD_LIMIT} bytes (LIMITED)\033[0m"
        echo "   -> Background systemd user services will default to 8 MiB limit."
    fi

    # Check file installation
    echo -n "3. PAM config (${PAM_DST}): "
    if [[ -f "${PAM_DST}" ]]; then
        echo -e "\033[0;32mINSTALLED\033[0m"
    else
        echo -e "\033[0;31mNOT INSTALLED\033[0m"
    fi

    echo -n "4. Systemd drop-in (${SYSTEMD_DST}): "
    if [[ -f "${SYSTEMD_DST}" ]]; then
        echo -e "\033[0;32mINSTALLED\033[0m"
    else
        echo -e "\033[0;31mNOT INSTALLED\033[0m"
    fi
    echo ""
}

show_commands() {
    cat <<EOF
To configure unlimited memlock on Metrotower, run the following commands with sudo:

  # 1. Install PAM limits for user sessions:
  sudo mkdir -p "$(dirname "${PAM_DST}")"
  sudo cp "${PAM_SRC}" "${PAM_DST}"
  sudo chmod 0644 "${PAM_DST}"

  # 2. Install systemd user session manager drop-in:
  sudo mkdir -p "${SYSTEMD_DROPIN_DIR}"
  sudo cp "${SYSTEMD_SRC}" "${SYSTEMD_DST}"
  sudo chmod 0644 "${SYSTEMD_DST}"

  # 3. Reload systemd daemon:
  sudo systemctl daemon-reload

  # 4. Activate changes for the current user session:
  systemctl --user daemon-reexec

Note: PAM limits in limits.d take effect on new login sessions (SSH, VT, or desktop re-login).
For user systemd services (e.g. berserker-llama.service), 'LimitMEMLOCK=infinity' is also
set directly in the unit file so it takes effect immediately when run under systemd.
EOF
}

install_files() {
    if [[ $EUID -ne 0 ]]; then
        echo "error: --install requires root privileges. Please run with sudo:" >&2
        echo "  sudo $(basename "$0") --install" >&2
        exit 1
    fi

    echo "Installing PAM limits to ${PAM_DST}..."
    # Arch/minimal installs may lack limits.d; create it (standard pam_limits path).
    mkdir -p "$(dirname "${PAM_DST}")"
    cp "${PAM_SRC}" "${PAM_DST}"
    chmod 0644 "${PAM_DST}"

    echo "Installing systemd drop-in to ${SYSTEMD_DST}..."
    mkdir -p "${SYSTEMD_DROPIN_DIR}"
    cp "${SYSTEMD_SRC}" "${SYSTEMD_DST}"
    chmod 0644 "${SYSTEMD_DST}"

    echo "Reloading systemd daemon..."
    systemctl daemon-reload

    echo ""
    echo "Configuration installed successfully."
    echo "Run 'systemctl --user daemon-reexec' in your user session to apply systemd changes."
}

MODE="check"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --status|--check)
            MODE="check"
            shift
            ;;
        --commands|--print)
            MODE="commands"
            shift
            ;;
        --install)
            MODE="install"
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Tool to check and configure RLIMIT_MEMLOCK for Metrotower llama-server.

Options:
    --status, --check    Check and print current memlock status (default)
    --commands           Print the exact sudo commands to install the configs
    --install            Install configuration files (requires sudo/root)
    -h, --help           Show this help message
EOF
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

case "${MODE}" in
    check)
        check_status
        show_commands
        ;;
    commands)
        show_commands
        ;;
    install)
        install_files
        ;;
esac
