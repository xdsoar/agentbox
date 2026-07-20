#!/usr/bin/env node

import { registerFonts } from "excalidrawer";

const XIAOLAI_PATH = "/usr/local/share/fonts/Xiaolai.ttf";

try {
  registerFonts(XIAOLAI_PATH);
} catch {
  // Xiaolai font not found. CJK text will fall back to system fonts.
}

const entryUrl = import.meta.resolve("excalidrawer");
const pkgRootUrl = new URL("..", entryUrl);
const mcpUrl = new URL("src/mcp.mjs", pkgRootUrl);
await import(mcpUrl.href);
