# agentbox

> Single-container sandbox for running Claude Code and OpenCode on macOS/Linux.
> The container is the security boundary — agents run fully autonomous (YOLO)
> inside, with **per-project mount policies** controlling what they can touch.

## Features

- **One image, two agents** — Claude Code and OpenCode pre-installed globally
- **Declarative environment** — define runtimes, caches, and setup commands in `.agent/devcontainer.json`
- **Smart container reuse** — hash-based change detection rebuilds only when config changes
- **Multi-session sharing** — multiple terminals share one container; auto-stops when the last session exits
- **Per-project isolation** — agent state (memory, config, history, caches) redirected into `./.agent/`, zero cross-project leakage
- **Pinned versions** — auto-updates disabled; upgrade by rebuilding the image
- **Blast-radius limits** — `no-new-privileges`, `cap_drop: ALL`, pids/mem/cpu caps, `/tmp` tmpfs

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (Desktop, OrbStack, or native)
- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)

## Quick Start

```bash
# Clone to a stable location
git clone https://github.com/example/agentbox.git ~/agentbox
cd ~/agentbox

# Configure your API credentials
cp .env.example .env && chmod 600 .env
# Edit .env: set DEEPSEEK_API_KEY (and optionally CLAUDE_CODE_OAUTH_TOKEN)

# Build the image
docker compose build

# Add the CLI to your PATH (writes the absolute path)
echo "export PATH=\"$(pwd)/bin:\$PATH\"" >> ~/.zshrc
source ~/.zshrc
```

> **DeepSeek**: set `DEEPSEEK_API_KEY` in `.env`.
> **Claude Code**: uses an OAuth subscription token, not an API key.
> Generate one with `agentbox claude setup-token`, then paste it into `.env` as `CLAUDE_CODE_OAUTH_TOKEN`.

## Usage

```bash
cd ~/code/my-project

# ── High-level (auto-starts container, stops when done) ──
agentbox                    # interactive shell inside the container
agentbox opencode           # launch OpenCode TUI
agentbox claude             # launch Claude Code
agentbox run <command>      # run a one-shot command

# ── Low-level (manual container management) ──
agentbox start              # ensure container is running (background)
agentbox stop               # stop container (respects active sessions)
agentbox rebuild            # force full rebuild
agentbox clean              # remove container, volumes, and state
agentbox status             # show container status and hashes
```

First run creates `./.agent/` in your project — **add it to `.gitignore`**:

```
.agent/
```

## Declarative Environment

Place a `.agent/devcontainer.json` in your project root to declare what the agent needs.
agentbox uses a subset of the [Dev Container spec](https://containers.dev/).

Copy the template to get started:

```bash
cp ~/agentbox/devcontainer.example.json .agent/devcontainer.json
```

### Example

```jsonc
{
  // Extend the base image with a custom Dockerfile
  "build": { "dockerfile": "./Dockerfile.dev" },

  // Or use a pre-built image directly
  // "image": "python:3.12-bookworm",

  // Environment variables inside the container
  "containerEnv": {
    "JAVA_HOME": "/usr/lib/jvm/msopenjdk-21"
  },

  // Persistent cache volumes (survive rebuilds)
  "mounts": [
    "source=maven-repo,target=/home/node/.m2/repository,type=volume"
  ],

  // Runs ONCE after container creation (dependency install, cache warm-up)
  "postCreateCommand": "pip install -r requirements.txt"
}
```

### How it works

| What changes | What happens |
|---|---|
| First run (no container) | `docker compose build` + `up -d` |
| Config unchanged | Reuses existing container (`docker compose start`) |
| Dockerfile or features changed | Destroys old container, rebuilds, recreates |
| `postCreateCommand` set | Executes once; skipped on container reuse |

Change detection uses `SHA-256(Dockerfile + project Dockerfile + features + image)`.

## Per-Project Mounts

Need the agent to access paths outside the project (shared libraries, data, SSH socket)?
Create a `.agentbox.yml` compose override in the project root:

```yaml
# .agentbox.yml
services:
  agent:
    volumes:
      - ~/libs/company-utils:/libs/company-utils:ro
      - ~/data/datasets:/data:ro
      - /run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock
    environment:
      - EXTRA_VAR=value
```

`.agentbox.yml` is a standard docker compose override — merged automatically at runtime.

## Security Model

| Layer | Strategy |
|---|---|
| **Container boundary** | `no-new-privileges`, `cap_drop: ALL`, pids=1024, mem=6g, cpus=4 |
| **Filesystem** | Only the project directory is mounted by default; `/tmp` is tmpfs |
| **Agent state** | Redirected to `./.agent/` per project — no `~/.claude` on the host |
| **Network egress** | No container-level filtering; control at your router/firewall (iKuai, OpenWrt) |
| **Secrets** | `.env` stays in the agentbox directory, `chmod 600`, never committed |

> **API keys are in the container's environment** — any agent process can read them.
> Mitigate with rotatable gateway tokens and network-level egress policies.

## DeepSeek V4 Pro Configuration

OpenCode and omo are pre-configured to use `deepseek/deepseek-v4-pro` exclusively:

- Uses the Anthropic-compatible endpoint (`@ai-sdk/anthropic`) for native reasoning/thinking stream support
- Every omo agent and category model rewritten to DeepSeek at build time
- Config seeded per-project on first run; verify with `omo doctor` inside the container

## Project Structure

```
agentbox/
├── bin/agentbox              CLI entry point
├── lib/
│   ├── container.sh          Container lifecycle (hash, create, rebuild)
│   ├── devcontainer.sh       devcontainer.json parsing & compose override
│   ├── session.sh            Multi-session tracking
│   └── volume.sh             Named volume management
├── docker-compose.yml        Base compose definition
├── Dockerfile                Image build
├── agent-init.sh             Container entrypoint (state init, postCreate)
├── devcontainer.example.json Template for .agent/devcontainer.json
├── .agentbox.example.yml     Template for per-project mounts
├── configure-deepseek.mjs    DeepSeek model pinning script
├── tests/                    Automated test suite
└── spec/                     Feature specs & design docs
```

## Known Boundaries

1. **Toolchain must live inside the container** — agents can't see compile/test results from the host. Add the project's runtime (python, jdk, cargo, etc.) via a custom Dockerfile.
2. **DeepSeek + tool calls**: multi-turn conversations with thinking + tool use require the thinking block to be echoed back, or the API may return 400.

## License

MIT
