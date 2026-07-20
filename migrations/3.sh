#!/usr/bin/env bash
# Migration v3: Clear stale oh-my-openagent plugin cache so OpenCode retries
# installation on next container start. Prior builds had a Docker named-volume
# permission bug that caused the plugin dependency install to fail silently.
set -euo pipefail

CACHE_DIR="$PROJECT_DIR/.agent/cache/opencode/packages/oh-my-openagent@latest"

if [ -d "$CACHE_DIR" ]; then
    echo "[migration] v3: clearing stale oh-my-openagent plugin cache"
    rm -rf "$CACHE_DIR"
else
    echo "[migration] v3: no stale plugin cache found, skipping."
fi

echo "[migration] v3: done."
