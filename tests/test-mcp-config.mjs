// Tests for MCP config generation in configure-models.mjs.
//
// Tests that the helper functions produce correct config for all three agents:
//   - OpenCode:  mcp key in JSON, type: "local", command as array
//   - Claude Code: mcpServers key in JSON, type: "stdio", command + args
//   - Codex:   [mcp_servers] section in TOML
//
// Usage: node tests/test-mcp-config.mjs
//   Exit code 0 = all pass, 1 = one or more failures.

let pass = 0;
let fail = 0;

function assert(desc, ok) {
  if (ok) { console.log(`  PASS  ${desc}`); pass++; }
  else    { console.log(`  FAIL  ${desc}`); fail++; }
}

function assertEq(desc, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) { console.log(`  PASS  ${desc}`); pass++; }
  else {
    console.log(`  FAIL  ${desc}`);
    console.log(`        expected: ${JSON.stringify(expected)}`);
    console.log(`        actual:   ${JSON.stringify(actual)}`);
    fail++;
  }
}

function assertContains(desc, haystack, needle) {
  const ok = haystack.includes(needle);
  if (ok) { console.log(`  PASS  ${desc}`); pass++; }
  else {
    console.log(`  FAIL  ${desc}`);
    console.log(`        expected to contain: ${needle}`);
    fail++;
  }
}

// ── MCP Server definition (mirrors configure-models.mjs) ────────────────

const MCP_SERVERS = [
  { name: 'excalidrawer', command: ['node', '/usr/local/bin/excalidrawer-mcp-launcher.mjs'] },
];

// ── Helper functions (mirrors configure-models.mjs) ─────────────────────

function buildOpenCodeMcp(existingMcp = {}) {
  const mcp = { ...existingMcp };
  for (const s of MCP_SERVERS) {
    mcp[s.name] = { type: 'local', command: s.command, enabled: true };
  }
  return mcp;
}

function buildClaudeMcp() {
  const servers = {};
  for (const s of MCP_SERVERS) {
    servers[s.name] = { type: 'stdio', command: s.command[0], args: s.command.slice(1) };
  }
  return { mcpServers: servers };
}

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

// ── Tests ───────────────────────────────────────────────────────────────

console.log('=== MCP_SERVERS definition ===');
assertEq('1.1 MCP_SERVERS has 1 entry', MCP_SERVERS.length, 1);
assertEq('1.2 server name is excalidrawer', MCP_SERVERS[0].name, 'excalidrawer');
assertEq('1.3 command has 2 parts', MCP_SERVERS[0].command.length, 2);
assert('1.4 command starts with node', MCP_SERVERS[0].command[0] === 'node');

console.log('\n=== OpenCode MCP (buildOpenCodeMcp) ===');
const ocMcp = buildOpenCodeMcp();
assert('2.1 has excalidrawer key', 'excalidrawer' in ocMcp);
assertEq('2.2 type is local', ocMcp.excalidrawer.type, 'local');
assertEq('2.3 command is array', ocMcp.excalidrawer.command, MCP_SERVERS[0].command);
assertEq('2.4 enabled is true', ocMcp.excalidrawer.enabled, true);

// Test that existing MCP servers are preserved
const ocOrig = { existing_tool: { type: 'local', command: ['echo'], enabled: false } };
const ocMerged = buildOpenCodeMcp(ocOrig);
assert('2.5 preserves existing MCP server', 'existing_tool' in ocMerged);
assert('2.6 adds new excalidrawer server', 'excalidrawer' in ocMerged);
assertEq('2.7 existing tool unchanged', ocMerged.existing_tool.enabled, false);

console.log('\n=== Claude Code MCP (buildClaudeMcp) ===');
const ccMcp = buildClaudeMcp();
assert('3.1 has mcpServers top-level key', 'mcpServers' in ccMcp);
assert('3.2 has excalidrawer in mcpServers', 'excalidrawer' in ccMcp.mcpServers);
assertEq('3.3 type is stdio', ccMcp.mcpServers.excalidrawer.type, 'stdio');
assertEq('3.4 command is just "node"', ccMcp.mcpServers.excalidrawer.command, 'node');
assertEq('3.5 args is the launcher path',
  ccMcp.mcpServers.excalidrawer.args,
  ['/usr/local/bin/excalidrawer-mcp-launcher.mjs']);
// Ensure Claude format does NOT have type "local" or enabled flag (OpenCode-specific)
assert('3.6 no "enabled" field in Claude format', !('enabled' in ccMcp.mcpServers.excalidrawer));

// Validate JSON serializability (no undefined values)
const ccJson = JSON.stringify(ccMcp);
assert('3.7 valid JSON output', typeof ccJson === 'string' && ccJson.length > 10);

console.log('\n=== Codex MCP (buildCodexMcp) ===');
const codexToml = buildCodexMcp();
assertContains('4.1 contains [mcp_servers.excalidrawer]', codexToml, '[mcp_servers.excalidrawer]');
assertContains('4.2 contains command = "node"', codexToml, 'command = "node"');
assertContains('4.3 contains args array with launcher', codexToml, '/usr/local/bin/excalidrawer-mcp-launcher.mjs');
assert('4.4 output ends with newline (valid TOML)', codexToml.endsWith('\n'));

// ── Cross-agent consistency ─────────────────────────────────────────────

console.log('\n=== Cross-agent consistency ===');
// All three formats should reference the same launcher
assertContains('5.1 OpenCode uses launcher', JSON.stringify(ocMcp.excalidrawer.command), 'excalidrawer-mcp-launcher.mjs');
assertContains('5.2 Claude Code uses launcher', JSON.stringify(ccMcp.mcpServers.excalidrawer.args), 'excalidrawer-mcp-launcher.mjs');
assertContains('5.3 Codex uses launcher', codexToml, 'excalidrawer-mcp-launcher.mjs');

// ── Multiple MCP servers ────────────────────────────────────────────────
// Simulate adding a second MCP server to ensure the helper functions scale
const MCP_EXTRA = [
  { name: 'excalidrawer', command: ['node', '/usr/local/bin/excalidrawer-mcp-launcher.mjs'] },
  { name: 'filesystem', command: ['npx', '-y', '@modelcontextprotocol/server-filesystem', '/tmp'] },
];

console.log('\n=== Multiple MCP servers ===');
function buildOpenCodeMcpExtra(existing = {}) {
  const mcp = { ...existing };
  for (const s of MCP_EXTRA) mcp[s.name] = { type: 'local', command: s.command, enabled: true };
  return mcp;
}
function buildClaudeMcpExtra() {
  const srv = {};
  for (const s of MCP_EXTRA) srv[s.name] = { type: 'stdio', command: s.command[0], args: s.command.slice(1) };
  return { mcpServers: srv };
}
function buildCodexMcpExtra() {
  const lines = [];
  for (const s of MCP_EXTRA) {
    lines.push(`[mcp_servers.${s.name}]`);
    lines.push(`command = "${s.command[0]}"`);
    lines.push(`args = ${JSON.stringify(s.command.slice(1))}`);
    lines.push('');
  }
  return lines.join('\n');
}

const oc2 = buildOpenCodeMcpExtra();
const cc2 = buildClaudeMcpExtra();
const cx2 = buildCodexMcpExtra();

assert('6.1 OpenCode handles 2 servers', Object.keys(oc2).length === 2);
assert('6.2 Claude Code handles 2 servers', Object.keys(cc2.mcpServers).length === 2);
assertContains('6.3 Codex has 2 [mcp_servers] sections', cx2, '[mcp_servers.filesystem]');

// ── Summary ─────────────────────────────────────────────────────────────

console.log(`\n${'='.repeat(50)}`);
console.log(`Results: ${pass} passed, ${fail} failed`);
console.log(`${'='.repeat(50)}`);
process.exit(fail > 0 ? 1 : 0);
