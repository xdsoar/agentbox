#!/usr/bin/env bash
# Migration v5: Fix excalidrawer MCP config — v4 wrote the wrong key (mcpServers
# instead of mcp). Remove the stale entry and re-register with correct format.
set -euo pipefail

OC_JSON="$PROJECT_DIR/.agent/config/opencode/opencode.json"

if [ ! -f "$OC_JSON" ]; then
    echo "[migration] v5: opencode.json not found — will be seeded on next container start."
    echo "[migration] v5: done."
    exit 0
fi

# 1. Remove stale mcpServers.excalidrawer written by buggy v4
if jq -e '.mcpServers.excalidrawer' "$OC_JSON" > /dev/null 2>&1; then
    echo "[migration] v5: removing stale mcpServers.excalidrawer (buggy v4 artifact)"
    jq 'del(.mcpServers.excalidrawer)' "$OC_JSON" > "$OC_JSON.tmp" && mv "$OC_JSON.tmp" "$OC_JSON"
    # If mcpServers is now empty, remove it entirely
    if jq -e '.mcpServers | length == 0' "$OC_JSON" > /dev/null 2>&1; then
        jq 'del(.mcpServers)' "$OC_JSON" > "$OC_JSON.tmp" && mv "$OC_JSON.tmp" "$OC_JSON"
    fi
fi

# 2. Ensure correct mcp.excalidrawer entry
if jq -e '.mcp.excalidrawer' "$OC_JSON" > /dev/null 2>&1; then
    echo "[migration] v5: excalidrawer MCP already registered, skipping."
else
    echo "[migration] v5: registering excalidrawer MCP server"
    jq '.mcp.excalidrawer = {
        "type": "local",
        "command": ["node", "/usr/local/bin/excalidrawer-mcp-launcher.mjs"],
        "enabled": true
    }' "$OC_JSON" > "$OC_JSON.tmp" && mv "$OC_JSON.tmp" "$OC_JSON"
fi

echo "[migration] v5: done."
