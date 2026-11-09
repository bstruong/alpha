#!/usr/bin/env bash
# Build and push alpha-runner to the Watchtower registry.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

IMAGE="${ALPHA_RUNNER_IMAGE:-registry.watchtower.local/alpha-runner:latest}"

echo "==> building ${IMAGE}"
docker build -f docker/alpha-runner/Dockerfile -t "${IMAGE}" .

echo "==> pushing ${IMAGE}"
docker push "${IMAGE}"
echo "ok  ${IMAGE}"
