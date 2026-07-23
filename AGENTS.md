# agentbox

> Single-container Docker sandbox for running AI coding agents (Claude Code / OpenCode) on macOS/Linux.
> The container is the security boundary — agents run fully autonomous (YOLO) inside, with per-project mount policies controlling what they can touch.

## Architecture

```
Host                              Docker Container
┌──────────────────┐             ┌──────────────────────────┐
│  ~/my-project     │──mount──→  │  /workspace              │
│  (source code)    │             │                          │
│                   │             │  opencode-ai (global)     │
│  .env             │──env──→    │  claude-code (global)     │
│                   │             │  codex (global)            │
│  API keys         │             │  oh-my-openagent (global) │
│                   │             │  typescript-lsp (global)  │
│  agentbox CLI     │             │  pyright (global)         │
└──────────────────┘             └──────────────────────────┘
```

- **Base image**: `node:22-bookworm-slim`
- **Globally installed**: `opencode-ai`, `@anthropic-ai/claude-code`, `@openai/codex`, `oh-my-openagent`, `typescript-language-server`, `pyright`, `python-lsp-server`, `excalidrawer` (diagram generation)
- **System fonts**: `fonts-noto-cjk` (CJK fallback), `Xiaolai` (hand-drawn CJK for Excalidraw)
- **NOT installed in container**: Playwright, browsers, any language runtimes beyond Node.js + Python
- **User**: `developer` (uid 1000), remapped from `node`

## Key Files

| File | Role |
|---|---|
| `Dockerfile` | Base image definition |
| `docker-compose.yml` | Container runtime config (env vars, volumes, limits) |
| `bin/agentbox` | CLI entry point (Bash) |
| `lib/container.sh` | Container lifecycle (hash detection, create/reuse/rebuild) |
| `lib/session.sh` | Multi-session tracking |
| `lib/devcontainer.sh` | `.agent/devcontainer.json` parser + compose override generation |
| `lib/volume.sh` | Named volume management |
| `agent-init.sh` | Container ENTRYPOINT — creates per-project state dirs, seeds OpenCode config, runs postCreate |
| `configure-models.mjs` | Build-time: configures DeepSeek + Gemini providers + generates MCP templates for all three agents |

## State Isolation

All agent state (memory, config, history, caches) is redirected into `./.agent/` inside the project. Never touches host `~/.claude` or `~/.config/opencode`. Add `.agent/` to `.gitignore`.

## Container Lifecycle

- **First run**: `docker compose build` → `up -d --wait`
- **Config unchanged**: Reuses existing container (`docker compose start`)
- **Dockerfile or devcontainer features changed**: Detects via SHA-256 hash → destroys old → rebuilds → recreates
- **postCreateCommand**: Executes once on first container creation; skipped on reuse
- **Auto-stop**: Container stops when last active session exits

## Extending the Container

Projects add a `.agent/devcontainer.json` to declare extra needs:

- `build.dockerfile` — extend the base image (e.g., install JDK, Rust, Playwright)
- `image` — use a completely different base image
- `features` — Dev Container community features (Java, Python, etc.)
- `mounts` — persistent named volumes for caches
- `postCreateCommand` — run once after container creation
- `containerEnv` — extra environment variables

Per-project extra mounts (SSH socket, shared libs) go in `.agentbox.yml` (docker compose override).

## Security

- `no-new-privileges`, `cap_drop: ALL`, pids=1024, mem=6g, cpus=4
- Only the project directory is mounted by default
- `/tmp` is tmpfs
- API keys are in container env — any agent process can read them

## Global MCP Tools

When adding a globally-installed MCP server (like `excalidrawer`), you **MUST** configure it for all three agents — not just OpenCode. Define the server once in `configure-models.mjs` → `MCP_SERVERS`, and the script auto-generates the three agent-specific configs.

### How It Works

| Agent | Config File | Location | Format |
|---|---|---|---|
| **OpenCode** | `opencode.json` | `.agent/config/opencode/` (seeded from `~/.config/opencode/` template) | `mcp` key in JSON: `type: "local"`, `command: [...]` |
| **Claude Code** | `claude.json` | `.agent/claude/` (CLAUDE_CONFIG_DIR) — user-scoped, per-project isolated | `mcpServers` key in JSON: `type: "stdio"`, `command` + `args` |
| **Codex** | `config.toml` | `~/.codex/` — user-scoped, per-container | `[mcp_servers.<name>]` section in TOML |

**Build time** (`configure-models.mjs`):
1. Define all MCP servers in the `MCP_SERVERS` array (name + command).
2. Three helper functions generate each agent's native format.
3. OpenCode config written directly to image template (`~/.config/opencode/opencode.json`).
4. Claude Code + Codex templates saved to `/home/developer/.agentbox/`.

**Runtime** (`agent-init.sh`, first run per project):
- OpenCode template → `.agent/config/opencode/`
- Claude Code template → `.agent/claude/claude.json`
- Codex template → `~/.codex/config.toml`

### Adding a New MCP Server

1. Add entry to `MCP_SERVERS` in `configure-models.mjs`.
2. Rebuild the image (`docker compose build`).
3. Delete `.agent/` in existing projects to pick up the new config on next run.

No other files need changes — the helper functions handle all three formats automatically.


