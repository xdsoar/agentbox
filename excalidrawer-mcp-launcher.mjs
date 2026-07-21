#!/usr/bin/env node

// Node.js ESM does NOT search global node_modules for bare specifiers.
// excalidrawer is installed globally at /usr/local/lib/node_modules/excalidrawer/
// during Docker build (npm install -g). Import it via explicit absolute paths
// so that the launcher works regardless of CWD or NODE_PATH.
const EXCALIDRAWER = "/usr/local/lib/node_modules/excalidrawer";

// Pre-register the Xiaolai CJK font for Chinese text in diagrams.
// If the font file is missing, CJK text falls back to NotoSansCJK (system).
try {
  const { registerFonts } = await import(`${EXCALIDRAWER}/src/index.mjs`);
  registerFonts("/usr/local/share/fonts/Xiaolai.ttf");
} catch {
  // Font not found — CJK text will use system NotoSansCJK fallback.
}

// Launch the excalidrawer MCP server (communicates over stdio).
await import(`${EXCALIDRAWER}/src/mcp.mjs`);
