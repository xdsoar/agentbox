// Force OpenCode + omo to use DeepSeek V4 Pro for text and Gemini for multimodal.
// Runs at build time, right after `oh-my-openagent install`, against the image's
// config TEMPLATE at ~/.config/opencode. agent-init.sh then seeds this per project.
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const DEEPSEEK_MODEL = 'deepseek/deepseek-v4-pro';
const GEMINI_MODEL = 'gemini/gemini-3.5-flash';
const HOME = process.env.HOME || '/home/developer';
const cfgDir = join(HOME, '.config', 'opencode');

// ── Global MCP servers ─────────────────────────────────────────────────────
// Define MCP servers ONCE here. When adding a new global MCP tool, define
// the server entry below — the three agent-specific configs are auto-generated.
// Template dir: /home/developer/.agentbox/  (seeded per-project by agent-init.sh)
//   - OpenCode:   .agent/config/opencode/opencode.json  (mcp key)
//   - Claude Code: .agent/claude/claude.json            (CLAUDE_CONFIG_DIR, mcpServers)
//   - Codex:       ~/.codex/config.toml                 (mcp_servers section)
// ───────────────────────────────────────────────────────────────────────────

/**
 * All globally-installed MCP servers. Each entry maps to all three agents.
 *
 * Fields:
 *   name    — server identifier (used as MCP key)
 *   command — array: [executable, ...args]
 */
const MCP_SERVERS = [
  {
    name: 'excalidrawer',
    command: ['node', '/usr/local/bin/excalidrawer-mcp-launcher.mjs'],
  },
];

/**
 * Generate OpenCode MCP config (JSON — `opencode.json` `mcp` key).
 */
function buildOpenCodeMcp(existingMcp = {}) {
  const mcp = { ...existingMcp };
  for (const s of MCP_SERVERS) {
    mcp[s.name] = {
      type: 'local',
      command: s.command,
      enabled: true,
    };
  }
  return mcp;
}

/**
 * Generate Claude Code MCP config (JSON — `~/.claude.json` or `.mcp.json`).
 */
function buildClaudeMcp() {
  const servers = {};
  for (const s of MCP_SERVERS) {
    servers[s.name] = {
      type: 'stdio',
      command: s.command[0],
      args: s.command.slice(1),
    };
  }
  return { mcpServers: servers };
}

/**
 * Generate Codex MCP config (TOML — `~/.codex/config.toml`).
 */
function buildCodexMcp() {
  const lines = [];
  for (const s of MCP_SERVERS) {
    lines.push(`[mcp_servers.${s.name}]`);
    lines.push(`command = "${s.command[0]}"`);
    lines.push(`args = ${JSON.stringify(s.command.slice(1))}`);
    lines.push('');
  }
  return lines.join('\n');
}

// Tolerant parse: omo may emit JSONC (// or /* */ comments). Try strict JSON first.
function parseLoose(text) {
  try {
    return JSON.parse(text);
  } catch {
    const stripped = text
      .replace(/\/\*[\s\S]*?\*\//g, '')          // block comments
      .replace(/(^|[^:])\/\/.*$/gm, '$1');       // line comments (keep "https://")
    return JSON.parse(stripped);
  }
}

// 1) opencode.json — add DeepSeek + Gemini providers. Merge, don't overwrite.
const ocPath = join(cfgDir, 'opencode.json');
const oc = existsSync(ocPath) ? parseLoose(readFileSync(ocPath, 'utf8')) : {};
oc['$schema'] = oc['$schema'] || 'https://opencode.ai/config.json';
oc.provider = oc.provider || {};

// DeepSeek provider (primary, for text tasks)
oc.provider.deepseek = {
  // Use DeepSeek's ANTHROPIC-compatible endpoint: @ai-sdk/anthropic natively parses
  // reasoning/thinking streams, whereas @ai-sdk/openai-compatible drops DeepSeek's private
  // `reasoning_content` field and hangs on reasoning models.
  npm: '@ai-sdk/anthropic',
  name: 'DeepSeek',
  options: {
    // Override at build with --build-arg DEEPSEEK_BASE_URL=... to point at a gateway.
    baseURL: process.env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com/anthropic',
    apiKey: '{env:DEEPSEEK_API_KEY}',
  },
  models: {
    'deepseek-v4-pro': {
      name: 'DeepSeek V4 Pro',
      options: { thinking: { type: 'enabled', budgetTokens: 8192 } },
    },
  },
};

// Gemini provider (for multimodal tasks — image/PDF recognition)
oc.provider.gemini = {
  npm: '@ai-sdk/google',
  name: 'Google Gemini',
  options: {
    apiKey: '{env:GEMINI_API_KEY}',
  },
  models: {
    'gemini-3.5-flash': {
      name: 'Gemini 3.5 Flash',
      options: {},
    },
  },
};

oc.model = DEEPSEEK_MODEL;
oc.small_model = DEEPSEEK_MODEL;
oc.autoupdate = false;

// Register global MCP servers in OpenCode config.
oc.mcp = buildOpenCodeMcp(oc.mcp);

writeFileSync(ocPath, JSON.stringify(oc, null, 2));
const mcpNames = MCP_SERVERS.map(s => s.name).join(', ');
console.log(`opencode.json -> default model ${DEEPSEEK_MODEL}, providers 'deepseek' + 'gemini', MCP: ${mcpNames}`);

// ── Claude Code MCP template (user-scoped, seeded to CLAUDE_CONFIG_DIR at runtime) ──
const tmplDir = join(HOME, '.agentbox');
mkdirSync(tmplDir, { recursive: true });

const claudeMcpPath = join(tmplDir, 'claude-mcp.json');
writeFileSync(claudeMcpPath, JSON.stringify(buildClaudeMcp(), null, 2));
console.log(`claude-mcp.json (template) -> MCP: ${mcpNames}`);

// ── Codex MCP template (user-scoped, seeded to ~/.codex/config.toml at runtime) ──
const codexMcpPath = join(tmplDir, 'codex-mcp.toml');
writeFileSync(codexMcpPath, buildCodexMcp());
console.log(`codex-mcp.toml (template) -> MCP: ${mcpNames}`);

// 2) omo agent config — pin agents by capability:
//    - Multimodal agents (multimodal-looker) → Gemini
//    - All other agents/categories → DeepSeek (default)
//    File name varies across omo versions (oh-my-openagent / oh-my-opencode, .json / .jsonc).
const omoFile = readdirSync(cfgDir).find((f) =>
  /^oh-my-(openagent|opencode)\.jsonc?$/.test(f),
);
if (omoFile) {
  const p = join(cfgDir, omoFile);
  const omo = parseLoose(readFileSync(p, 'utf8'));
  let deepseekCount = 0;
  let geminiCount = 0;

  // Agents that need multimodal capability (image / PDF interpretation)
  const MULTIMODAL_AGENTS = ['multimodal-looker'];

  for (const bucket of ['agents', 'categories']) {
    if (omo[bucket] && typeof omo[bucket] === 'object') {
      for (const k of Object.keys(omo[bucket])) {
        omo[bucket][k] = omo[bucket][k] || {};

        if (MULTIMODAL_AGENTS.includes(k)) {
          // Multimodal agent → Gemini (no fallback — explicit API key required)
          omo[bucket][k].model = GEMINI_MODEL;
          delete omo[bucket][k].variant;
          delete omo[bucket][k].fallback;
          geminiCount++;
        } else {
          // Text-only agent → DeepSeek
          omo[bucket][k].model = DEEPSEEK_MODEL;
          delete omo[bucket][k].variant;
          delete omo[bucket][k].fallback;
          deepseekCount++;
        }
      }
    }
  }
  writeFileSync(p, JSON.stringify(omo, null, 2));
  console.log(`${omoFile} -> ${deepseekCount} agents/categories → ${DEEPSEEK_MODEL}, ${geminiCount} → ${GEMINI_MODEL}`);
} else {
  console.log('omo config not found; pin agents manually after first run.');
}
