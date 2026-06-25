#!/usr/bin/env bash
# volume.sh — Docker volume management for agentbox.
#
# Creates and cleans up persistent cache volumes declared in devcontainer.json
# mounts field. Named volumes (type=volume) are created on first use and
# preserved across container rebuilds.

set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────

# Extract named volume sources from devcontainer mount definitions.
# Mount format: "source=<name>,target=<path>,type=volume"
_parse_volume_names() {
    if [ -z "${AGENTBOX_MOUNTS:-}" ]; then
        return
    fi
    echo "$AGENTBOX_MOUNTS" | while IFS= read -r mount; do
        # Only handle type=volume mounts
        if echo "$mount" | grep -q 'type=volume'; then
            echo "$mount" | grep -oP 'source=\K[^,]+' 2>/dev/null || true
        fi
    done
}

# ── public API ───────────────────────────────────────────────────────────

# Create all named volumes declared in devcontainer.json.
# Idempotent: docker volume create is a no-op if volume already exists.
volume_create_all() {
    local volumes
    volumes=$(_parse_volume_names)
    if [ -z "$volumes" ]; then
        return 0
    fi
    echo "$volumes" | while IFS= read -r vol; do
        if [ -n "$vol" ]; then
            docker volume create "$vol" >/dev/null 2>&1 || true
        fi
    done
}

# Remove project-scoped volumes (cache volumes shared across projects are NOT removed).
# Only removes volumes that were declared in this project's devcontainer.json.
volume_cleanup() {
    local volumes
    volumes=$(_parse_volume_names)
    if [ -z "$volumes" ]; then
        return 0
    fi
    echo "[agentbox] Removing project volumes..."
    echo "$volumes" | while IFS= read -r vol; do
        if [ -n "$vol" ]; then
            docker volume rm "$vol" >/dev/null 2>&1 || {
                echo "[agentbox] WARNING: Could not remove volume: $vol (may be in use)" >&2
            }
        fi
    done
}
