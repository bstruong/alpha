# Alpha campaign runner for Watchtower Jobs (CPU client to JARVIS).
# Build: ./docker/alpha-runner/build-push.sh
#
# Phase 2 isolation requires bubblewrap plus a runtime that permits
# unprivileged user namespaces (seccomp/AppArmor must not block clone).
# Missing sandbox support is infrastructure-invalid — never unsandboxed.
FROM ruby:4.0.7-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    ALPHA_CHROME_PATH=/usr/bin/chromium \
    CHROMIUM_FLAGS="--no-sandbox --disable-dev-shm-usage" \
    LANG=C.UTF-8

# Node 22 for Pi harness (Debian bookworm ships Node 18).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git patch build-essential gnupg \
      bubblewrap \
      chromium chromium-driver \
      python3 \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /usr/local/bin/kubectl \
         "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && node -v && npm -v

# Pre-bake Pi harness deps (postinstall needs bin/).
WORKDIR /opt/alpha-build
COPY harness/pi/ /opt/alpha-build/harness/pi/
RUN cd harness/pi && npm ci --omit=dev \
    && mkdir -p /opt/pi-harness \
    && cp -a . /opt/pi-harness/ \
    && rm -rf /opt/alpha-build

ENV PI_BIN=/opt/pi-harness/node_modules/.bin/pi

WORKDIR /workspace
CMD ["/bin/bash"]
