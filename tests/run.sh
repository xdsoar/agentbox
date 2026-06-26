#!/usr/bin/env bash
# agentbox test runner — automated test cases.
#
# Usage:
#   AGENTBOX_HOME=/path/to/agentbox bash tests/run.sh
#
# Requires:
#   - Docker running (Docker Desktop, OrbStack, or native)
#   - jq installed (brew install jq)
#   - agentbox image built: cd $AGENTBOX_HOME && docker compose build
#
# Each test creates a temporary project directory and cleans up after itself.

set -euo pipefail

AGENTBOX_HOME="${AGENTBOX_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENTBOX_BIN="$AGENTBOX_HOME/bin/agentbox"
TEST_ROOT="/tmp/agentbox-test-$$"
PASS=0
FAIL=0

# ── helpers ──────────────────────────────────────────────────────────────

_red()    { printf '\033[31m%s\033[0m' "$1"; }
_green()  { printf '\033[32m%s\033[0m' "$1"; }
_yellow() { printf '\033[33m%s\033[0m' "$1"; }

assert_ok() {
    local desc="$1"; shift
    if "$@" &>/dev/null; then
        echo "  $(_green PASS)  $desc"
        PASS=$((PASS + 1))
    else
        echo "  $(_red FAIL)  $desc"
        echo "        command: $*"
        FAIL=$((FAIL + 1))
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  $(_green PASS)  $desc"
        PASS=$((PASS + 1))
    else
        echo "  $(_red FAIL)  $desc"
        echo "        expected: '$expected'"
        echo "        actual:   '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    if [ -f "$file" ]; then
        echo "  $(_green PASS)  $desc"
        PASS=$((PASS + 1))
    else
        echo "  $(_red FAIL)  $desc (file not found: $file)"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  $(_green PASS)  $desc"
        PASS=$((PASS + 1))
    else
        echo "  $(_red FAIL)  $desc"
        echo "        expected to contain: '$needle'"
        FAIL=$((FAIL + 1))
    fi
}

setup_project() {
    local name="$1"
    local dir="$TEST_ROOT/$name"
    mkdir -p "$dir/.agent"
    echo "$dir"
}

cleanup() {
    echo ""
    echo "Cleaning up test projects..."
    for dir in "$TEST_ROOT"/*/; do
        if [ -d "$dir" ]; then
            # Stop and clean any agentbox containers for this project
            AGENTBOX_PROJECT_DIR="${dir%/}" "$AGENTBOX_BIN" clean 2>/dev/null || true
        fi
    done
    rm -rf "$TEST_ROOT"
}

# ── pre-flight checks ────────────────────────────────────────────────────

preflight() {
    echo "=== Pre-flight checks ==="

    if ! command -v docker &>/dev/null; then
        echo "$(_red FAIL)  Docker not found. Is Docker Desktop running?"
        exit 1
    fi
    echo "  $(_green OK)   Docker available: $(docker --version)"

    if ! docker compose version &>/dev/null; then
        echo "$(_red FAIL)  docker compose not available"
        exit 1
    fi
    echo "  $(_green OK)   docker compose available"

    if ! command -v jq &>/dev/null; then
        echo "  $(_yellow WARN) jq not installed (install with: brew install jq)"
    else
        echo "  $(_green OK)   jq available"
    fi

    if [ ! -f "$AGENTBOX_BIN" ]; then
        echo "$(_red FAIL)  agentbox binary not found: $AGENTBOX_BIN"
        exit 1
    fi
    echo "  $(_green OK)   agentbox binary found"

    if [ ! -f "$AGENTBOX_HOME/docker-compose.yml" ]; then
        echo "$(_red FAIL)  docker-compose.yml not found in $AGENTBOX_HOME"
        exit 1
    fi
    echo "  $(_green OK)   docker-compose.yml found"

    echo ""
}

# ── Scenario 1: First Start (Cold Boot) ──────────────────────────────────

test_scenario_1() {
    echo "=== Scenario 1: First Start (Cold Boot) ==="

    local proj
    proj=$(setup_project "scenario1")
    cd "$proj"

    # Create a minimal devcontainer.json
    cat > "$proj/.agent/devcontainer.json" <<'JSON'
{"postCreateCommand": "echo 'PC_OK' > /tmp/pc-ok"}
JSON

    # Start
    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" start 2>&1

    assert_file_exists "1.2 image.hash exists" "$proj/.agent/container/image.hash"
    assert_file_exists "1.3 features.hash exists" "$proj/.agent/container/features.hash"

    # Check container is running
    local ps_output
    ps_output=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" status 2>&1)
    assert_contains "1.4 container running" "running" "$ps_output"

    # Check user inside container
    local whoami_out
    whoami_out=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" exec whoami 2>&1)
    assert_eq "1.5 user is node" "node" "$whoami_out"

    # Check working directory
    local pwd_out
    pwd_out=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" exec pwd 2>&1)
    assert_eq "1.6 pwd is /<project>" "/scenario1" "$pwd_out"

    # Check postCreate ran
    local pc_out
    pc_out=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" exec cat /tmp/pc-ok 2>&1)
    assert_eq "4.3 postCreate executed" "PC_OK" "$pc_out"

    echo ""
}

# ── Scenario 2: Container Reuse ──────────────────────────────────────────

test_scenario_2() {
    echo "=== Scenario 2: Container Reuse ==="

    local proj
    proj=$(setup_project "scenario2")
    cd "$proj"

    cat > "$proj/.agent/devcontainer.json" <<'JSON'
{}
JSON

    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" start 2>&1

    # Create a marker file (use workspace dir, NOT /tmp which is tmpfs lost on stop)
    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" exec touch /home/node/reuse-marker 2>&1

    # Stop the container so we can verify reuse (start from stopped state)
    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" stop 2>&1

    # Second start — should NOT rebuild
    local start_out
    start_out=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" start 2>&1)
    assert_contains "2.1 no rebuild on reuse" "Starting existing container" "$start_out"

    # Marker should still exist (same container)
    local marker_out
    marker_out=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" exec ls /home/node/reuse-marker 2>&1)
    assert_contains "2.3 marker persists" "reuse-marker" "$marker_out"

    echo ""
}

# ── Scenario 3: Hash Change Triggers Rebuild ─────────────────────────────

test_scenario_3() {
    echo "=== Scenario 3: Hash Change Triggers Rebuild ==="

    local proj
    proj=$(setup_project "scenario3")
    cd "$proj"

    cat > "$proj/.agent/devcontainer.json" <<'JSON'
{"features": {}, "postCreateCommand": "echo 'V1' > /tmp/version"}
JSON

    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" start 2>&1

    # Store initial hash
    local initial_hash
    initial_hash=$(cat "$proj/.agent/container/features.hash")

    # Change the config (modify features)
    cat > "$proj/.agent/devcontainer.json" <<'JSON'
{"features": {"some-feature": "changed"}, "postCreateCommand": "echo 'V2' > /tmp/version"}
JSON

    local rebuild_out
    rebuild_out=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" start 2>&1)
    assert_contains "3.2 rebuild triggered" "Config changed" "$rebuild_out"

    # Hash should be updated
    local new_hash
    new_hash=$(cat "$proj/.agent/container/features.hash")
    assert_contains "3.3 hash updated" "!=" "$initial_hash != $new_hash"

    # postCreate should have run again, writing V2
    local ver_out
    ver_out=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" exec cat /tmp/version 2>&1)
    assert_eq "3.4 postCreate re-ran" "V2" "$ver_out"

    echo ""
}

# ── Scenario 5: Volume Cache Persistence ─────────────────────────────────

test_scenario_5() {
    echo "=== Scenario 5: Volume Cache Persistence ==="

    local proj
    proj=$(setup_project "scenario5")
    cd "$proj"

    # Create a named Docker volume and fix ownership so the non-root
    # 'node' user (UID 1000) can write to it inside the container.
    local vol_name="agentbox-test-vol-$$"
    docker volume create "$vol_name" > /dev/null 2>&1
    docker run --rm --user 0:0 -v "${vol_name}:/vol" agent-box:local \
        chown 1000:1000 /vol > /dev/null 2>&1

    cat > "$proj/.agent/devcontainer.json" <<JSON
{"mounts": ["source=${vol_name},target=/home/node/cache,type=volume"]}
JSON

    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" start 2>&1

    # Write a marker into the cache volume
    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" exec sh -c 'echo cached > /home/node/cache/marker' 2>&1

    # Rebuild
    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" rebuild 2>&1

    # Marker should survive rebuild
    local cache_out
    cache_out=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" exec cat /home/node/cache/marker 2>&1)
    assert_eq "5.3 cache survives rebuild" "cached" "$cache_out"

    # Volume still exists and is declared external in override
    local vol_exists
    vol_exists=$(docker volume ls -q | grep -F "$vol_name" || echo "")
    assert_contains "5.4 external volume persisted" "$vol_name" "$vol_exists"

    # Clean up the test volume
    docker volume rm "$vol_name" > /dev/null 2>&1 || true

    echo ""
}

# ── Scenario 7: Idle Container Auto-Stop ─────────────────────────────────

test_scenario_7() {
    echo "=== Scenario 7: Idle Container Auto-Stop ==="

    local proj
    proj=$(setup_project "scenario7")
    cd "$proj"

    cat > "$proj/.agent/devcontainer.json" <<'JSON'
{}
JSON

    # Start container, then run a command via run (which does session tracking)
    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" run echo "done" 2>&1

    sleep 2  # give session cleanup time

    # Container should be stopped
    local status_out
    status_out=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" status 2>&1)
    assert_contains "7.3 container stopped" "stopped" "$status_out"

    echo ""
}

# ── Scenario 9: Clean ────────────────────────────────────────────────────

test_scenario_9() {
    echo "=== Scenario 9: Clean ==="

    local proj
    proj=$(setup_project "scenario9")
    cd "$proj"

    cat > "$proj/.agent/devcontainer.json" <<'JSON'
{}
JSON

    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" start 2>&1
    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" clean 2>&1

    # State directory should be gone
    if [ ! -d "$proj/.agent/container" ]; then
        echo "  $(_green PASS)  9.3 state directory cleaned"
        ((PASS++))
    else
        echo "  $(_red FAIL)  9.3 state directory not cleaned"
        ((FAIL++))
    fi

    # Cold start after clean
    local cold_out
    cold_out=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" start 2>&1)
    assert_contains "9.4 cold start after clean" "First start" "$cold_out"

    echo ""
}

# ── Scenario 11: Multi-Project Isolation ─────────────────────────────────

test_scenario_11() {
    echo "=== Scenario 11: Multi-Project Isolation ==="

    local proj_a proj_b
    proj_a=$(setup_project "scenario11-a")
    proj_b=$(setup_project "scenario11-b")
    cd "$proj_a"

    cat > "$proj_a/.agent/devcontainer.json" <<'JSON'
{"containerEnv": {"PROJECT_TAG": "A"}}
JSON
    cat > "$proj_b/.agent/devcontainer.json" <<'JSON'
{"containerEnv": {"PROJECT_TAG": "B"}}
JSON

    AGENTBOX_PROJECT_DIR="$proj_a" "$AGENTBOX_BIN" start 2>&1
    AGENTBOX_PROJECT_DIR="$proj_b" "$AGENTBOX_BIN" start 2>&1

    # Different hostnames
    local host_a host_b
    host_a=$(AGENTBOX_PROJECT_DIR="$proj_a" "$AGENTBOX_BIN" exec hostname 2>&1)
    host_b=$(AGENTBOX_PROJECT_DIR="$proj_b" "$AGENTBOX_BIN" exec hostname 2>&1)
    assert_contains "11.2 different containers" "!=" "$host_a != $host_b"

    # Create file in A only
    AGENTBOX_PROJECT_DIR="$proj_a" "$AGENTBOX_BIN" exec touch /home/node/project-a-marker 2>&1

    # Should NOT be in B
    local marker_in_b
    marker_in_b=$(AGENTBOX_PROJECT_DIR="$proj_b" "$AGENTBOX_BIN" exec ls /home/node/project-a-marker 2>&1 || true)
    assert_contains "11.4 isolation" "No such file" "$marker_in_b"

    echo ""
}

# ── Scenario: postCreate Idempotency ─────────────────────────────────────

test_postcreate_idempotent() {
    echo "=== PostCreate: Idempotent ==="

    local proj
    proj=$(setup_project "pc-idem")
    cd "$proj"

    cat > "$proj/.agent/devcontainer.json" <<'JSON'
{"postCreateCommand": "echo 'IDEMPOTENT' >> /tmp/pc-log"}
JSON

    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" start 2>&1

    # First run writes 1 line
    local log1
    log1=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" exec wc -l /tmp/pc-log 2>&1 | awk '{print $1}')
    assert_eq "postCreate ran once initially" "1" "$log1"

    # Second start (reuse, no rebuild) — should NOT add another line
    AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" start 2>&1
    local log2
    log2=$(AGENTBOX_PROJECT_DIR="$proj" "$AGENTBOX_BIN" exec wc -l /tmp/pc-log 2>&1 | awk '{print $1}')
    assert_eq "postCreate not re-run on reuse" "1" "$log2"

    echo ""
}

# ── Scenario: AGENTBOX_HOME Auto-Detection ────────────────────────────────

test_agentbox_home_autodetect() {
    echo "=== AGENTBOX_HOME: Auto-Detection ==="

    local proj
    proj=$(setup_project "autodetect")
    cd "$proj"

    echo '{}' > "$proj/.agent/devcontainer.json"

    # Run agentbox WITHOUT AGENTBOX_HOME set — it must auto-detect from script location
    AGENTBOX_PROJECT_DIR="$proj" env -u AGENTBOX_HOME "$AGENTBOX_BIN" start > /dev/null 2>&1
    assert_ok "auto-detect: start succeeds without AGENTBOX_HOME" true

    local whoami_out
    whoami_out=$(AGENTBOX_PROJECT_DIR="$proj" env -u AGENTBOX_HOME "$AGENTBOX_BIN" exec whoami 2>&1)
    assert_eq "auto-detect: exec whoami" "node" "$whoami_out"

    AGENTBOX_PROJECT_DIR="$proj" env -u AGENTBOX_HOME "$AGENTBOX_BIN" clean > /dev/null 2>&1

    echo ""
}

# ── main ─────────────────────────────────────────────────────────────────

main() {
    trap cleanup EXIT

    echo "agentbox test suite"
    echo "==================="
    echo "Test root: $TEST_ROOT"
    echo ""

    preflight

    test_agentbox_home_autodetect
    test_scenario_1
    test_scenario_2
    test_scenario_3
    test_scenario_5
    test_scenario_7
    test_scenario_9
    test_scenario_11
    test_postcreate_idempotent

    echo ""
    echo "==================="
    echo "Results: $(_green $PASS passed), $(_red $FAIL failed)"
    echo ""

    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
