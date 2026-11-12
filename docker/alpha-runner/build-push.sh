#!/usr/bin/env bash
# Build and push alpha-runner to the Watchtower registry; print immutable digest.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

TAG="${ALPHA_RUNNER_TAG:-$(git -C "${ROOT}" rev-parse --short=12 HEAD)}"
IMAGE_BASE="${ALPHA_RUNNER_IMAGE_BASE:-registry.watchtower.local/alpha-runner}"
IMAGE_TAGGED="${IMAGE_BASE}:${TAG}"

echo "==> building ${IMAGE_TAGGED}"
docker build -f docker/alpha-runner/Dockerfile -t "${IMAGE_TAGGED}" .

echo "==> pushing ${IMAGE_TAGGED}"
docker push "${IMAGE_TAGGED}"

digest="$(docker image inspect "${IMAGE_TAGGED}" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
if [[ -z "${digest}" ]]; then
  # Fallback: query registry after push
  digest="$(docker buildx imagetools inspect "${IMAGE_TAGGED}" 2>/dev/null | awk '/Digest:/ {print $2; exit}')"
  if [[ -n "${digest}" ]]; then
    digest="${IMAGE_BASE}@${digest}"
  fi
fi

echo "ok  tagged=${IMAGE_TAGGED}"
if [[ -n "${digest}" ]]; then
  echo "ok  digest=${digest}"
  echo "ALPHA_RUNNER_IMAGE=${digest}"
else
  echo "warn: could not resolve RepoDigest; pin manually before graded kick" >&2
  echo "ALPHA_RUNNER_IMAGE=${IMAGE_TAGGED}"
fi
