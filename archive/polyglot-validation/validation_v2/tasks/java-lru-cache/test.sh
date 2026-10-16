#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "=== java-lru-cache ==="
javac LRUCache.java
java -ea LRUCache
echo "=== java-lru-cache: PASS ==="
