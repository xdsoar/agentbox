// Force OpenCode + omo to use ONLY deepseek/deepseek-v4-pro.
// Runs at build time, right after `oh-my-openagent install`, against the image's
// config TEMPLATE at ~/.config/opencode. agent-init.sh then seeds this per project.
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const MODEL = 'deepseek/deepseek-v4-pro';
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

// 1) opencode.json — add the DeepSeek provider and make it the default everywhere.
//    Merge, don't overwrite: omo already put a `plugin` entry here.
const ocPath = join(cfgDir, 'opencode.json');
const oc = existsSync(ocPath) ? parseLoose(readFileSync(ocPath, 'utf8')) : {};
oc['$schema'] = oc['$schema'] || 'https://opencode.ai/config.json';
oc.provider = oc.provider || {};
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
oc.model = MODEL;
oc.small_model = MODEL;
oc.autoupdate = false;
writeFileSync(ocPath, JSON.stringify(oc, null, 2));
console.log(`opencode.json -> default model ${MODEL}, provider 'deepseek' added`);

// 2) omo agent config — pin EVERY agent and category to the one model, drop any
//    variant/fallback that referenced other providers. File name varies across
//    omo versions (oh-my-openagent / oh-my-opencode, .json / .jsonc).
const omoFile = readdirSync(cfgDir).find((f) =>
  /^oh-my-(openagent|opencode)\.jsonc?$/.test(f),
);
if (omoFile) {
  const p = join(cfgDir, omoFile);
  const omo = parseLoose(readFileSync(p, 'utf8'));
  let n = 0;
  for (const bucket of ['agents', 'categories']) {
    if (omo[bucket] && typeof omo[bucket] === 'object') {
      for (const k of Object.keys(omo[bucket])) {
        omo[bucket][k] = omo[bucket][k] || {};
        omo[bucket][k].model = MODEL;
        delete omo[bucket][k].variant;
        delete omo[bucket][k].fallback;
        n++;
      }
    }
  }
  writeFileSync(p, JSON.stringify(omo, null, 2));
  console.log(`${omoFile} -> pinned ${n} agents/categories to ${MODEL}`);
} else {
  console.log('omo config not found; pin agents manually after first run.');
}
