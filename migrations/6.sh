#!/usr/bin/env bash
# Migration v6: Seed Claude Code MCP config into existing projects.
# New global MCP servers (excalidrawer) now ship with config templates for all three
# agents. Claude Code's user-scoped MCP lives under CLAUDE_CONFIG_DIR (project .agent/).
# Codex MCP is handled by agent-init.sh at container start — it writes to ~/.codex/
# inside the container, which is not accessible from host-side migrations.
set -euo pipefail

CLAUDE_JSON="$PROJECT_DIR/.agent/claude/claude.json"
TEMPLATE="/home/developer/.agentbox/claude-mcp.json"

if [ -f "$CLAUDE_JSON" ]; then
    echo "[migration] v6: Claude Code config already exists, skipping."
else
    if [ -f "$TEMPLATE" ]; then
        mkdir -p "$(dirname "$CLAUDE_JSON")"
        cp "$TEMPLATE" "$CLAUDE_JSON"
        echo "[migration] v6: seeded Claude Code MCP config -> $CLAUDE_JSON"
    else
        echo "[migration] v6: WARNING: template not found at $TEMPLATE — rebuild image first."
    fi
fi

echo "[migration] v6: Codex MCP config will be seeded at next container start (agent-init.sh)."
echo "[migration] v6: done."
