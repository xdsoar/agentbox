#!/usr/bin/env bash
# Migration v6: Seed Claude Code + Codex MCP config into existing projects.
# New global MCP servers (excalidrawer) now ship with config templates for all three
# agents. OpenCode MCP was seeded by migrations/4 and /5.
#
# Claude Code: config lives under CLAUDE_CONFIG_DIR (= .agent/claude/), writable from host.
# Codex: config lives at ~/.codex/config.toml INSIDE the container. Migration writes a
#        seed file to .agent/codex-mcp-seed.toml; agent-init.sh picks it up on next start.
set -euo pipefail

CLAUDE_JSON="$PROJECT_DIR/.agent/claude/claude.json"
CODEX_SEED="$PROJECT_DIR/.agent/codex-mcp-seed.toml"

# ── Claude Code ───────────────────────────────────────────────────────────

if [ -f "$CLAUDE_JSON" ]; then
    echo "[migration] v6: Claude Code config already exists, skipping."
else
    mkdir -p "$(dirname "$CLAUDE_JSON")"
    cat > "$CLAUDE_JSON" <<'JSON'
{
  "mcpServers": {
    "excalidrawer": {
      "type": "stdio",
      "command": "node",
      "args": ["/usr/local/bin/excalidrawer-mcp-launcher.mjs"]
    }
  }
}
JSON
    echo "[migration] v6: seeded Claude Code MCP config -> $CLAUDE_JSON"
fi

# ── Codex (seed for agent-init.sh) ────────────────────────────────────────

if [ -f "$CODEX_SEED" ]; then
    echo "[migration] v6: Codex seed already exists, skipping."
else
    cat > "$CODEX_SEED" <<'TOML'
[mcp_servers.excalidrawer]
command = "node"
args = ["/usr/local/bin/excalidrawer-mcp-launcher.mjs"]

TOML
    echo "[migration] v6: wrote Codex MCP seed -> $CODEX_SEED (agent-init.sh will apply it)"
fi

echo "[migration] v6: done."
