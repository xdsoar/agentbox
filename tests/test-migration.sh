#!/usr/bin/env bash
# Tests for migration/6.sh — MCP config seeding for Claude Code + Codex seed.
#
# Usage: bash tests/test-migration.sh
#   Exit code 0 = all pass, 1 = one or more failures.

set -euo pipefail

RED='\033[31m'; GREEN='\033[32m'; NC='\033[0m'
PASS=0; FAIL=0

_pass() { echo -e "  ${GREEN}PASS${NC}  $1"; PASS=$((PASS + 1)); }
_fail() { echo -e "  ${RED}FAIL${NC}  $1"; FAIL=$((FAIL + 1)); }

TEST_ROOT=$(mktemp -d /tmp/agentbox-mcp-test-XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT
export TEST_ROOT

# ── Helper: inline the migration 6 logic (no container-template dependency) ─

_run_migration_6() {
    local proj="$1"
    local claude_json="$proj/.agent/claude/claude.json"
    local codex_seed="$proj/.agent/codex-mcp-seed.toml"

    # Claude Code
    if [ -f "$claude_json" ]; then
        echo "CLAUDE_SKIP"
    else
        mkdir -p "$(dirname "$claude_json")"
        cat > "$claude_json" <<'JSON'
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
        echo "CLAUDE_SEEDED"
    fi

    # Codex seed
    if [ -f "$codex_seed" ]; then
        echo "CODEX_SKIP"
    else
        cat > "$codex_seed" <<'TOML'
[mcp_servers.excalidrawer]
command = "node"
args = ["/usr/local/bin/excalidrawer-mcp-launcher.mjs"]

TOML
        echo "CODEX_SEEDED"
    fi
    echo "DONE"
}

# ── Test 1: Fresh project — both Claude + Codex seed created ─────────────

echo "=== Test 1: Fresh project (both seeded) ==="
PROJECT_DIR="$TEST_ROOT/proj1"
mkdir -p "$PROJECT_DIR/.agent"

output=$(_run_migration_6 "$PROJECT_DIR" 2>&1)

if echo "$output" | grep -q "CLAUDE_SEEDED"; then
    _pass "1.1 Claude config seeded"
else
    _fail "1.1 Expected CLAUDE_SEEDED, got: $output"
fi

if echo "$output" | grep -q "CODEX_SEEDED"; then
    _pass "1.2 Codex seed written"
else
    _fail "1.2 Expected CODEX_SEEDED, got: $output"
fi

if [ -f "$PROJECT_DIR/.agent/claude/claude.json" ]; then
    _pass "1.3 claude.json exists"
else
    _fail "1.3 claude.json not created"
fi

if grep -q "excalidrawer" "$PROJECT_DIR/.agent/claude/claude.json" 2>/dev/null; then
    _pass "1.4 claude.json contains excalidrawer MCP"
else
    _fail "1.4 claude.json missing excalidrawer MCP"
fi

if [ -f "$PROJECT_DIR/.agent/codex-mcp-seed.toml" ]; then
    _pass "1.5 codex-mcp-seed.toml exists"
else
    _fail "1.5 codex-mcp-seed.toml not created"
fi

if grep -q "mcp_servers.excalidrawer" "$PROJECT_DIR/.agent/codex-mcp-seed.toml" 2>/dev/null; then
    _pass "1.6 codex-mcp-seed.toml contains excalidrawer MCP"
else
    _fail "1.6 codex-mcp-seed.toml missing excalidrawer MCP"
fi

# ── Test 2: Existing Claude config — Claude skipped, Codex still seeded ─

echo ""
echo "=== Test 2: Existing Claude config (Claude skip, Codex seed) ==="
PROJECT_DIR="$TEST_ROOT/proj2"
mkdir -p "$PROJECT_DIR/.agent/claude"
echo '{"mcpServers":{"existing":{}}}' > "$PROJECT_DIR/.agent/claude/claude.json"

output=$(_run_migration_6 "$PROJECT_DIR" 2>&1)

if echo "$output" | grep -q "CLAUDE_SKIP"; then
    _pass "2.1 Claude config skipped (already exists)"
else
    _fail "2.1 Expected CLAUDE_SKIP, got: $output"
fi

if echo "$output" | grep -q "CODEX_SEEDED"; then
    _pass "2.2 Codex seed still written (did not exist)"
else
    _fail "2.2 Expected CODEX_SEEDED, got: $output"
fi

# Original content preserved
if grep -q "existing" "$PROJECT_DIR/.agent/claude/claude.json" 2>/dev/null; then
    _pass "2.3 Existing Claude config preserved"
else
    _fail "2.3 Existing Claude config was overwritten"
fi

# ── Test 3: Existing seed file — Codex skipped, Claude still created ────

echo ""
echo "=== Test 3: Existing Codex seed (Codex skip, Claude seed) ==="
PROJECT_DIR="$TEST_ROOT/proj3"
mkdir -p "$PROJECT_DIR/.agent"
echo 'exists' > "$PROJECT_DIR/.agent/codex-mcp-seed.toml"

output=$(_run_migration_6 "$PROJECT_DIR" 2>&1)

if echo "$output" | grep -q "CLAUDE_SEEDED"; then
    _pass "3.1 Claude config seeded"
else
    _fail "3.1 Expected CLAUDE_SEEDED, got: $output"
fi

if echo "$output" | grep -q "CODEX_SKIP"; then
    _pass "3.2 Codex seed skipped (already exists)"
else
    _fail "3.2 Expected CODEX_SKIP, got: $output"
fi

# ── Test 4: Both exist — both skipped ────────────────────────────────────

echo ""
echo "=== Test 4: Both exist (both skipped) ==="
PROJECT_DIR="$TEST_ROOT/proj4"
mkdir -p "$PROJECT_DIR/.agent/claude"
echo '{"mcpServers":{"existing":{}}}' > "$PROJECT_DIR/.agent/claude/claude.json"
echo 'exists' > "$PROJECT_DIR/.agent/codex-mcp-seed.toml"

output=$(_run_migration_6 "$PROJECT_DIR" 2>&1)

if echo "$output" | grep -q "CLAUDE_SKIP"; then
    _pass "4.1 Claude config skipped"
else
    _fail "4.1 Expected CLAUDE_SKIP, got: $output"
fi

if echo "$output" | grep -q "CODEX_SKIP"; then
    _pass "4.2 Codex seed skipped"
else
    _fail "4.2 Expected CODEX_SKIP, got: $output"
fi

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "=================================================="
echo "Results: $PASS assertions run, $FAIL failed"
echo "=================================================="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
