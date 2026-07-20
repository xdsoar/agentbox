#!/usr/bin/env bash
set -euo pipefail

# Create the per-project, isolated agent-state directories inside the mounted workspace.
# Everything the agents persist — memory, config, history, caches — lands under ./.agent,
# so two projects never share state. Wipe a project's agent memory with: rm -rf .agent
for d in \
    "${CLAUDE_CONFIG_DIR:-/${PROJECT_NAME:-workspace}/.agent/claude}" \
    "${XDG_CONFIG_HOME:-/${PROJECT_NAME:-workspace}/.agent/config}" \
    "${XDG_DATA_HOME:-/${PROJECT_NAME:-workspace}/.agent/data}" \
    "${XDG_STATE_HOME:-/${PROJECT_NAME:-workspace}/.agent/state}" \
    "${XDG_CACHE_HOME:-/${PROJECT_NAME:-workspace}/.agent/cache}"; do
    mkdir -p "$d"
done

# Initialize agentbox migration version marker on first run.
# Derive .agent/ root from XDG_CONFIG_HOME (always set by docker-compose).
_agent_root="$(dirname "${XDG_CONFIG_HOME:-/${PROJECT_NAME:-workspace}/.agent/config}")"
if [ ! -f "$_agent_root/version" ]; then
    echo "0" > "$_agent_root/version"
fi

# Seed the pre-installed OpenCode + omo config into this project on first run.
# The image ships a template at /home/developer/.config/opencode (built by `oh-my-openagent install`).
# Each project gets its own editable copy, so omo is ready everywhere without re-installing,
# while project configs stay isolated. Delete ./.agent to reset to the shipped template.
OPENCODE_TEMPLATE="/home/developer/.config/opencode"
OPENCODE_PROJECT="${XDG_CONFIG_HOME:-/${PROJECT_NAME:-workspace}/.agent/config}/opencode"
if [ -d "$OPENCODE_TEMPLATE" ] && [ ! -e "$OPENCODE_PROJECT" ]; then
    mkdir -p "$(dirname "$OPENCODE_PROJECT")"
    cp -a "$OPENCODE_TEMPLATE" "$OPENCODE_PROJECT"
fi

# Run postCreate hook if injected by agentbox CLI on container creation.
# The script is mounted at /.agentbox/post-create.sh and is only present
# on the FIRST start after container creation (agentbox removes it after execution).
if [ -f "/.agentbox/post-create.sh" ]; then
    echo "[agentbox] Running postCreate command..."
    bash "/.agentbox/post-create.sh" || echo "[agentbox] WARNING: postCreate command failed" >&2
fi

# Redirect npm + pip caches into the workspace to avoid Docker named-volume
# permission issues (named volumes are root-owned; the workspace is bind-mounted
# with the correct host UID). Without this, OpenCode's plugin dependency install
# fails with EACCES on /home/developer/.npm/_cacache.
export npm_config_cache="${XDG_CACHE_HOME:-/${PROJECT_NAME:-workspace}/.agent/cache}/npm"
export PIP_CACHE_DIR="${XDG_CACHE_HOME:-/${PROJECT_NAME:-workspace}/.agent/cache}/pip"
mkdir -p "$npm_config_cache" "$PIP_CACHE_DIR"

exec "$@"
