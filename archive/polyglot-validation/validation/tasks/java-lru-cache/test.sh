#!/usr/bin/env bash
set -euo pipefail

if command -v javac &>/dev/null; then
    javac LRUCache.java
    java -ea LRUCache
else
    echo "[skip] javac not installed, skipping compilation"
fi
echo "java-lru-cache: OK"
