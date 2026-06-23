# syntax=docker/dockerfile:1

# Unified "agent box": Claude Code + OpenCode in one image.
# The container itself is the security boundary — run the agents in YOLO mode *inside* here,
# and let per-project volume mounts decide what they can actually touch.
FROM node:22-bookworm-slim

# Pin versions for reproducible, deliberate upgrades (override at build time).
ARG CLAUDE_CODE_VERSION=latest
ARG OPENCODE_VERSION=latest
ARG OMO_VERSION=latest
ARG DEEPSEEK_BASE_URL=https://api.deepseek.com/anthropic

# Base tooling the agents expect: git, ripgrep (code search), curl/ca-certs, less, procps.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ripgrep \
        curl \
        ca-certificates \
        less \
        procps \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install the agents + the omo CLI globally to /usr/local so a per-project HOME/volume
# can never shadow them. (omo is dual-published; 'oh-my-openagent' is the current name.)
RUN npm install -g \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "opencode-ai@${OPENCODE_VERSION}" \
        "oh-my-openagent@${OMO_VERSION}" \
    && npm cache clean --force

# Convenience launcher: Claude Code with permission prompts skipped.
# This is safe ONLY because we are inside the container sandbox.
RUN printf '#!/usr/bin/env bash\nexec claude --dangerously-skip-permissions "$@"\n' \
        > /usr/local/bin/claude-yolo \
    && chmod +x /usr/local/bin/claude-yolo

# Entry hook that creates the per-project state dirs before launching anything.
# --chmod=0755 so the non-root 'node' user can READ and EXECUTE it (a script needs both;
# plain `chmod +x` would add execute without read and break shebang execution).
COPY --chmod=0755 agent-init.sh /usr/local/bin/agent-init.sh

# Build-time config: pin OpenCode + omo to deepseek-v4-pro only.
# --chmod=0644 so the non-root 'node' user (which runs it below) can read it.
COPY --chmod=0644 configure-deepseek.mjs /usr/local/lib/configure-deepseek.mjs

# The node base image already ships a non-root 'node' user at uid/gid 1000.
# Using it keeps bind-mounted file ownership sane on macOS Docker / OrbStack.
USER node
WORKDIR /workspace

# Pre-install omo (oh-my-openagent) into OpenCode. This writes a config TEMPLATE into the
# image at /home/node/.config/opencode (omo plugin registration + agent->model map).
# agent-init.sh seeds a per-project copy from this on first run, so omo is ready in every
# project while project configs stay isolated.
#   --no-tui          : run the installer non-interactively (no subscription interview)
#   --platform=opencode : Ultimate edition (OpenCode), not the Codex Light edition
#   --claude=no ...     : we don't use any of omo's built-in providers — every agent gets
#                         rewritten to deepseek by configure-deepseek.mjs below, so these
#                         yes/no values don't affect the final config.
# The omo plugin's own deps are fetched by OpenCode on first run (one-time network per project,
# cached under that project's .agent/cache). For an air-gapped build, point npm/bun at an
# internal mirror and pre-warm that cache.
# NOTE: in --no-tui mode omo wants ALL provider flags stated explicitly.
ARG OMO_INSTALL_FLAGS="--no-tui --platform=opencode --claude=no --openai=no --gemini=no --copilot=no"
RUN oh-my-openagent install ${OMO_INSTALL_FLAGS}

# Pin OpenCode's default and every omo agent/category to deepseek-v4-pro only.
RUN DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL}" node /usr/local/lib/configure-deepseek.mjs

ENTRYPOINT ["/usr/local/bin/agent-init.sh"]
CMD ["bash"]
