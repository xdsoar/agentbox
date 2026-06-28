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

# Base tooling: git, ripgrep, curl/ca-certs, less, procps, python, vim, and common
# Unix utilities AI agents frequently invoke (grep/sed/awk/find/xargs).
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ripgrep \
        curl \
        ca-certificates \
        less \
        procps \
        openssh-client \
        python3 \
        python3-pip \
        python3-venv \
        python-is-python3 \
        vim \
        grep \
        sed \
        gawk \
        findutils \
    && rm -rf /var/lib/apt/lists/*

# Install the agents + the omo CLI globally to /usr/local so a per-project HOME/volume
# can never shadow them. (omo is dual-published; 'oh-my-openagent' is the current name.)
# Also install language servers for the built-in runtimes so agents can inspect / refactor
# TypeScript/JavaScript and Python code without per-project setup.
RUN npm install -g \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "opencode-ai@${OPENCODE_VERSION}" \
        "oh-my-openagent@${OMO_VERSION}" \
        "typescript-language-server" \
        "pyright" \
    && npm cache clean --force

# Python LSP toolchain complementing pyright (above) — rope-based refactoring,
# jedi-powered completions. Installed globally as root so every project benefits.
RUN pip3 install --no-cache-dir --break-system-packages python-lsp-server

# Convenience launcher: Claude Code with permission prompts skipped.
# This is safe ONLY because we are inside the container sandbox.
RUN printf '#!/usr/bin/env bash\nexec claude --dangerously-skip-permissions "$@"\n' \
        > /usr/local/bin/claude-yolo \
    && chmod +x /usr/local/bin/claude-yolo

# Entry hook that creates the per-project state dirs before launching anything.
COPY agent-init.sh /usr/local/bin/agent-init.sh
RUN chmod 0755 /usr/local/bin/agent-init.sh

# Build-time config: set up DeepSeek (text) + Gemini (multimodal) providers.
COPY configure-models.mjs /usr/local/lib/configure-models.mjs
RUN chmod 0644 /usr/local/lib/configure-models.mjs

RUN usermod -l developer -d /home/developer -m node
RUN rmdir /workspace 2>/dev/null || true
USER developer
WORKDIR /home/developer

# Pre-install omo (oh-my-openagent) into OpenCode. This writes a config TEMPLATE into the
# image at /home/developer/.config/opencode (omo plugin registration + agent->model map).
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
ARG OMO_INSTALL_FLAGS="--no-tui --platform=opencode --claude=no --openai=no --gemini=yes --copilot=no"
RUN oh-my-openagent install ${OMO_INSTALL_FLAGS}

# Configure models: DeepSeek for text agents, Gemini for multimodal agents.
RUN DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL}" node /usr/local/lib/configure-models.mjs

ENTRYPOINT ["/usr/local/bin/agent-init.sh"]
CMD ["bash"]
