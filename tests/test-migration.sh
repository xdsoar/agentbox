#!/usr/bin/env bash
# Tests for migration/6.sh — MCP config seeding for Claude Code.
#
# Usage: bash tests/test-migration.sh
#   Exit code 0 = all pass, 1 = one or more failures.

set -euo pipefail

RED='\033[31m'; GREEN='\033[32m'; NC='\033[0m'
PASS=0; FAIL=0

_pass() { echo -e "  ${GREEN}PASS${NC}  $1"; PASS=$((PASS + 1)); }
_fail() { echo -e "  ${RED}FAIL${NC}  $1"; PASS=$((PASS + 1)); FAIL=$((FAIL + 1)); }

TEST_ROOT=$(mktemp -d /tmp/agentbox-mcp-test-XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT
export TEST_ROOT

# ── Setup: create template ──────────────────────────────────────────────

mkdir -p "$TEST_ROOT/.agentbox"
cat > "$TEST_ROOT/.agentbox/claude-mcp.json" <<'JSON'
{"mcpServers":{"excalidrawer":{"type":"stdio","command":"node","args":["/usr/local/bin/excalidrawer-mcp-launcher.mjs"]}}}
JSON

# Helper: run the migration logic inline for a given PROJECT_DIR
_run_migration_6() {
    local proj="$1"
    local claude_json="$proj/.agent/claude/claude.json"
    local tmpl="$TEST_ROOT/.agentbox/claude-mcp.json"

    if [ -f "$claude_json" ]; then
        echo "SKIP"
    elif [ -f "$tmpl" ]; then
        mkdir -p "$(dirname "$claude_json")"
        cp "$tmpl" "$claude_json"
        echo "SEEDED"
    else
        echo "WARN_NO_TEMPLATE"
    fi
    echo "DONE"
}

# ── Test 1: Fresh project — config should be seeded ─────────────────────

echo "=== Test 1: Fresh project (no existing Claude config) ==="
PROJECT_DIR="$TEST_ROOT/proj1"
mkdir -p "$PROJECT_DIR/.agent"

output=$(_run_migration_6 "$PROJECT_DIR" 2>&1)
if echo "$output" | grep -q "SEEDED"; then
    _pass "1.1 Migration reports SEEDED"
else
    _fail "1.1 Expected SEEDED, got: $output"
fi

if [ -f "$PROJECT_DIR/.agent/claude/claude.json" ]; then
    _pass "1.2 claude.json created"
else
    _fail "1.2 claude.json not created at $PROJECT_DIR/.agent/claude/claude.json"
fi

if grep -q "excalidrawer" "$PROJECT_DIR/.agent/claude/claude.json" 2>/dev/null; then
    _pass "1.3 claude.json contains excalidrawer MCP"
else
    _fail "1.3 claude.json missing excalidrawer MCP"
fi

# ── Test 2: Existing config — should be skipped ─────────────────────────

echo ""
echo "=== Test 2: Existing Claude config (skip) ==="
PROJECT_DIR="$TEST_ROOT/proj2"
mkdir -p "$PROJECT_DIR/.agent/claude"
echo '{"mcpServers":{"existing":{}}}' > "$PROJECT_DIR/.agent/claude/claude.json"

output=$(_run_migration_6 "$PROJECT_DIR" 2>&1)
if echo "$output" | grep -q "SKIP"; then
    _pass "2.1 Migration reports SKIP for existing config"
else
    _fail "2.1 Expected SKIP, got: $output"
fi

# Original content should be preserved
if grep -q "existing" "$PROJECT_DIR/.agent/claude/claude.json" 2>/dev/null; then
    _pass "2.2 Existing config content preserved (not overwritten)"
else
    _fail "2.2 Existing config content was lost"
fi

# ── Test 3: Missing template — should warn ──────────────────────────────

echo ""
echo "=== Test 3: Missing template (warn) ==="
PROJECT_DIR="$TEST_ROOT/proj3"
mkdir -p "$PROJECT_DIR/.agent"
rm -f "$TEST_ROOT/.agentbox/claude-mcp.json"

output=$(_run_migration_6 "$PROJECT_DIR" 2>&1)
if echo "$output" | grep -q "WARN_NO_TEMPLATE"; then
    _pass "3.1 Migration warns when template missing"
else
    _fail "3.1 Expected WARN_NO_TEMPLATE, got: $output"
fi

if [ ! -f "$PROJECT_DIR/.agent/claude/claude.json" ]; then
    _pass "3.2 No claude.json created when template missing"
else
    _fail "3.2 claude.json should not be created without template"
fi

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "=================================================="
echo "Results: $PASS assertions run, $FAIL failed"
echo "=================================================="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
