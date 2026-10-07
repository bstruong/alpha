#!/usr/bin/env bash
# Thin wrapper: start Qwen 3.8 Flash via the engine presets in engine/models.ini.
# Client-facing model id (OpenAI `model` field) = section name: qwen3.8-flash (alias qwen-3.8-flash also routes).
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${REPO_DIR}/engine/bin/llama-up.sh" single qwen3.8-flash "$@"
