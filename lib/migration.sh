#!/usr/bin/env bash
# migration.sh — version-based project migration for agentbox.
#
# Each project stores its current migration version in .agent/version.
# On every agentbox invocation, if the project version is behind the
# agentbox target version, migration scripts in $AGENTBOX_HOME/migrations/
# are executed in order: from current+1 up to target (e.g., if current=0
# and target=3, executes 1.sh → 2.sh → 3.sh).
#
# Bump AGENTBOX_MIGRATION_VERSION when adding a new migration script.

set -euo pipefail

AGENTBOX_MIGRATION_VERSION=2

_migration_version_file() {
    echo "$PROJECT_DIR/.agent/version"
}

_migration_read_version() {
    local vf
    vf="$(_migration_version_file)"
    if [ -f "$vf" ]; then
        cat "$vf"
    else
        echo "0"
    fi
}

_migration_write_version() {
    local v="$1"
    local vf
    vf="$(_migration_version_file)"
    mkdir -p "$(dirname "$vf")"
    echo "$v" > "$vf"
}

migration_check() {
    local current target
    current="$(_migration_read_version)"
    target="$AGENTBOX_MIGRATION_VERSION"

    if [ "$current" -ge "$target" ]; then
        return 0
    fi

    echo "[agentbox] Project migration: v${current} → v${target}"
    local v="$current"
    while [ "$v" -lt "$target" ]; do
        local next=$((v + 1))
        local script="$AGENTBOX_HOME/migrations/${next}.sh"
        if [ -f "$script" ]; then
            echo "[agentbox] Running migration: ${next}"
            bash "$script" || {
                echo "[agentbox] ERROR: Migration ${next} failed. Aborting." >&2
                return 1
            }
        else
            echo "[agentbox] WARNING: Migration script ${next}.sh not found, skipping."
        fi
        v="$next"
        _migration_write_version "$v"
    done
    echo "[agentbox] Migration complete: v${target}"
}
