// Force OpenCode + omo to use DeepSeek V4 Pro for text and Gemini for multimodal.
// Runs at build time, right after `oh-my-openagent install`, against the image's
// config TEMPLATE at ~/.config/opencode. agent-init.sh then seeds this per project.
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const DEEPSEEK_MODEL = 'deepseek/deepseek-v4-pro';
const GEMINI_MODEL = 'gemini/gemini-3.5-flash';
const HOME = process.env.HOME || '/home/developer';
const cfgDir = join(HOME, '.config', 'opencode');

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
writeFileSync(ocPath, JSON.stringify(oc, null, 2));
console.log(`opencode.json -> default model ${DEEPSEEK_MODEL}, providers 'deepseek' + 'gemini' added`);

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
