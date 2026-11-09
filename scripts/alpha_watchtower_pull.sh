#!/usr/bin/env bash
# Optional: pull Watchtower PVC artifacts onto this machine for alpha-lab promote.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB="${ALPHA_LAB_ROOT:-${HOME}/Projects/alpha-lab}"
WATCHTOWER_SSH="${WATCHTOWER_SSH:-watchtower}"
REMOTE="${ALPHA_WATCHTOWER_ARTIFACTS:-/mnt/appdata/alpha/artifacts}"

echo "==> pulling reports/qualifications/logs from ${WATCHTOWER_SSH}:${REMOTE}"
mkdir -p "${ROOT}/reports" "${ROOT}/qualifications" "${ROOT}/results/logs" \
         "${LAB}/reports" "${LAB}/qualifications"

rsync -az --progress \
  "${WATCHTOWER_SSH}:${REMOTE}/reports/" "${ROOT}/reports/" || true
rsync -az --progress \
  "${WATCHTOWER_SSH}:${REMOTE}/qualifications/" "${ROOT}/qualifications/" || true
rsync -az --progress \
  "${WATCHTOWER_SSH}:${REMOTE}/results/logs/" "${ROOT}/results/logs/" || true

# Mirror shipping quals + live map into alpha-lab for local promote workflow.
if [[ -d "${LAB}" ]]; then
  rsync -az "${WATCHTOWER_SSH}:${REMOTE}/reports/" "${LAB}/reports/" || true
  rsync -az "${WATCHTOWER_SSH}:${REMOTE}/qualifications/" "${LAB}/qualifications/" || true
  echo "ok  mirrored into ${LAB}"
fi

echo "Next (optional):"
echo "  cd ${ROOT} && ALPHA_ROOT=${LAB} mise exec -- bin/alpha qualify --manifest"
echo "  ALPHA_ROOT=${LAB} mise exec -- bin/alpha qualify --list"
