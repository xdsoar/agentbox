#!/usr/bin/env bash
# Migration v4: Register excalidrawer MCP server in project opencode config.
# The image now ships excalidrawer + Xiaolai CJK font; existing projects need
# the MCP server entry added so agents can generate hand-drawn diagrams.
set -euo pipefail

OC_JSON="$PROJECT_DIR/.agent/config/opencode/opencode.json"

if [ ! -f "$OC_JSON" ]; then
    echo "[migration] v4: opencode.json not found — will be seeded on next container start."
    echo "[migration] v4: done."
    exit 0
fi

if jq -e '.mcpServers.excalidrawer' "$OC_JSON" > /dev/null 2>&1; then
    echo "[migration] v4: excalidrawer MCP already registered, skipping."
else
    echo "[migration] v4: registering excalidrawer MCP server"
    jq '.mcpServers.excalidrawer = {
        "command": "node",
        "args": ["/usr/local/bin/excalidrawer-mcp-launcher.mjs"]
    }' "$OC_JSON" > "$OC_JSON.tmp" && mv "$OC_JSON.tmp" "$OC_JSON"
fi

echo "[migration] v4: done."
