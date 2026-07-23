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
| **Codex** | `config.toml` | `$CODEX_HOME` (default: `~/.codex`; docker-compose sets to `.agent/codex/`) — user-scoped, per-project persisted via bind mount | `[mcp_servers.<name>]` section in TOML |

**Build time** (`configure-models.mjs`):
1. Define all MCP servers in the `MCP_SERVERS` array (name + command).
2. Three helper functions generate each agent's native format.
3. OpenCode config written directly to image template (`~/.config/opencode/opencode.json`).
4. Claude Code + Codex templates saved to `/home/developer/.agentbox/`.

**Runtime** (`agent-init.sh`, first run per project):
- OpenCode template → `.agent/config/opencode/`
- Claude Code template → `.agent/claude/claude.json`
- Codex template → `$CODEX_HOME/config.toml` (.agent/codex/)

### Adding a New MCP Server

1. Add entry to `MCP_SERVERS` in `configure-models.mjs`.
2. Write a migration script (`migrations/<next-version>.sh`) that appends the new MCP server to existing config files:
   - **OpenCode**: add entry under `.mcp` in `.agent/config/opencode/opencode.json` (use `jq`)
   - **Claude Code**: add entry under `.mcpServers` in `.agent/claude/claude.json` (use `jq`)
   - **Codex**: append `[mcp_servers.<name>]` block to `$CODEX_HOME/config.toml` — but since Codex config lives inside the container, the migration can write a seed file to `.agent/codex-mcp-seed.toml` and `agent-init.sh` picks it up on next container start
3. Bump `AGENTBOX_MIGRATION_VERSION` in `lib/migration.sh`.
4. Rebuild the image (`docker compose build`).

Existing projects will pick up the new MCP server through the migration on next `agentbox start`.
New projects get it automatically via `agent-init.sh` seeding.

No other files need changes — the helper functions handle all three formats automatically.


