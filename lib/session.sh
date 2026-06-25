#!/usr/bin/env bash
# session.sh — multi-session tracking for agentbox containers.
#
# One container, multiple simultaneous `agentbox enter`/`agentbox opencode` sessions.
# The container is stopped only when ALL sessions have exited.
#
# Session markers: .agent/container/sessions/<session-id> (empty files).

set -euo pipefail

_session_dir() {
    echo "$PROJECT_DIR/.agent/container/sessions"
}

# Generate a unique session ID (PID + timestamp).
_session_id() {
    echo "ses-$$-$(date +%s)"
}

# ── public API ───────────────────────────────────────────────────────────

# Register this process as an active session.
session_register() {
    local dir sid
    dir="$(_session_dir)"
    sid="$(_session_id)"
    mkdir -p "$dir"
    touch "$dir/$sid"
    echo "$sid"  # return session ID for potential use
}

# Remove this session's marker.
session_unregister() {
    local dir sid
    dir="$(_session_dir)"
    sid="$(_session_id)"
    if [ -f "$dir/$sid" ]; then
        rm -f "$dir/$sid"
    fi
    # Clean up the sessions directory if empty
    if [ -d "$dir" ] && [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        rmdir "$dir" 2>/dev/null || true
    fi
}

# Check if any active sessions remain.
session_has_active() {
    local dir
    dir="$(_session_dir)"
    if [ ! -d "$dir" ]; then
        return 1  # no sessions directory = no sessions
    fi
    # Check if any session files have values
    [ -n "$(ls -A "$dir" 2>/dev/null)" ]
}

# Number of active sessions.
session_count() {
    local dir
    dir="$(_session_dir)"
    if [ ! -d "$dir" ]; then
        echo 0
        return
    fi
    ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' '
}
