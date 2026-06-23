#!/usr/bin/env bash
set -euo pipefail

# Create the per-project, isolated agent-state directories inside the mounted workspace.
# Everything the agents persist — memory, config, history, caches — lands under ./.agent,
# so two projects never share state. Wipe a project's agent memory with: rm -rf .agent
for d in \
    "${CLAUDE_CONFIG_DIR:-/workspace/.agent/claude}" \
    "${XDG_CONFIG_HOME:-/workspace/.agent/config}" \
    "${XDG_DATA_HOME:-/workspace/.agent/data}" \
    "${XDG_STATE_HOME:-/workspace/.agent/state}" \
    "${XDG_CACHE_HOME:-/workspace/.agent/cache}"; do
    mkdir -p "$d"
done

# Seed the pre-installed OpenCode + omo config into this project on first run.
# The image ships a template at /home/node/.config/opencode (built by `oh-my-openagent install`).
# Each project gets its own editable copy, so omo is ready everywhere without re-installing,
# while project configs stay isolated. Delete ./.agent to reset to the shipped template.
OPENCODE_TEMPLATE="/home/node/.config/opencode"
OPENCODE_PROJECT="${XDG_CONFIG_HOME:-/workspace/.agent/config}/opencode"
if [ -d "$OPENCODE_TEMPLATE" ] && [ ! -e "$OPENCODE_PROJECT" ]; then
    mkdir -p "$(dirname "$OPENCODE_PROJECT")"
    cp -a "$OPENCODE_TEMPLATE" "$OPENCODE_PROJECT"
fi

exec "$@"
