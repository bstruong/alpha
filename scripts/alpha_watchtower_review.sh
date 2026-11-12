#!/usr/bin/env bash
# Review the latest campaign report/log in place on Watchtower disk.
set -euo pipefail

WATCHTOWER_SSH="${WATCHTOWER_SSH:-watchtower}"
ARTIFACTS="${ALPHA_WATCHTOWER_ARTIFACTS:-/mnt/appdata/alpha/artifacts}"
WHAT="${1:-map}" # map | log | list

case "${WHAT}" in
  list)
    ssh "${WATCHTOWER_SSH}" "ls -lt ${ARTIFACTS}/reports 2>/dev/null | head -20; echo; ls -lt ${ARTIFACTS}/results/logs 2>/dev/null | head -20"
    ;;
  log)
    ssh "${WATCHTOWER_SSH}" "bash -lc 'f=\$(ls -t ${ARTIFACTS}/results/logs/*.log 2>/dev/null | head -1); echo \"=== \$f ===\"; sed -n \"1,80p;\\\$p\" \"\$f\" 2>/dev/null | head -100'"
    ;;
  map|*)
    ssh "${WATCHTOWER_SSH}" "bash -lc '
      f=${ARTIFACTS}/reports/CAPABILITY_MAP_LIVE.md
      if [[ -f \$f ]]; then echo \"=== \$f ===\"; cat \"\$f\";
      else echo \"No CAPABILITY_MAP_LIVE.md yet\"; ls -lt ${ARTIFACTS}/reports 2>/dev/null | head -15; fi
    '"
    ;;
esac
