#!/usr/bin/env bash
# Run Phase 2 isolation escape fixtures on the host and (optionally) inside the
# alpha-runner image. Graded campaigns still run only as Watchtower Jobs; this
# script is a development/diagnostic check, not a graded runner.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

echo "==> host: bubblewrap probe"
if ! command -v bwrap >/dev/null 2>&1; then
  echo "FAIL: bwrap not installed on host" >&2
  exit 1
fi
bwrap --version || true

echo "==> host: isolation unit tests"
mise exec -- bundle exec ruby -Itest test/isolation_escape_test.rb

IMAGE="${ALPHA_RUNNER_IMAGE:-registry.watchtower.local/alpha-runner:latest}"
if ! command -v docker >/dev/null 2>&1; then
  echo "skip docker image path: docker not available"
  exit 0
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "skip docker image path: ${IMAGE} not present locally"
  echo "build with: ./docker/alpha-runner/build-push.sh (or docker build -f docker/alpha-runner/Dockerfile)"
  exit 0
fi

echo "==> image: checking ${IMAGE} for bubblewrap"
IMAGE_HAS_BWRAP=0
if docker run --rm "${IMAGE}" bash -lc 'command -v bwrap && bwrap --version'; then
  IMAGE_HAS_BWRAP=1
  echo "ok  image has bubblewrap"
else
  echo "warn  ${IMAGE} lacks bubblewrap (rebuild required)"
fi

# Bubblewrap needs unprivileged user namespaces. Docker's default seccomp/AppArmor
# profiles often block them; Watchtower Jobs must allow the equivalent (seccomp
# unconfined or an explicit userns-capable profile). Never fall back to bare exec.
DOCKER_SEC=(--security-opt seccomp=unconfined --security-opt apparmor=unconfined)

run_image_fixtures() {
  local tag="$1"
  docker run --rm "${DOCKER_SEC[@]}" \
    -v "${ROOT}:/workspace:ro" \
    -w /workspace \
    "${tag}" \
    bash -lc 'command -v bwrap && bwrap --version && ruby -Itest test/isolation_escape_test.rb'
}

# Full fixture run inside a rebuild candidate when ALPHA_ISOLATION_IMAGE_BUILD=1,
# or against the existing image when it already contains bubblewrap.
if [[ "${ALPHA_ISOLATION_IMAGE_BUILD:-}" == "1" ]]; then
  echo "==> building local isolation validation image"
  LOCAL_TAG="alpha-runner:isolation-validate"
  docker build -f docker/alpha-runner/Dockerfile -t "${LOCAL_TAG}" .
  run_image_fixtures "${LOCAL_TAG}"
elif [[ "${IMAGE_HAS_BWRAP}" == "1" ]]; then
  run_image_fixtures "${IMAGE}"
else
  echo "FAIL: runner image lacks bubblewrap; rebuild with ./docker/alpha-runner/build-push.sh" >&2
  echo "      or re-run: ALPHA_ISOLATION_IMAGE_BUILD=1 ./scripts/validate_isolation.sh" >&2
  exit 1
fi

echo "ok  isolation validation complete"
