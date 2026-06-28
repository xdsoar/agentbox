#!/usr/bin/env bash
# Migration v2: Add Gemini provider and route multimodal-looker to it.
set -euo pipefail

OC_DIR="$PROJECT_DIR/.agent/config/opencode"
OC_JSON="$OC_DIR/opencode.json"

# Find omo config (name varies: oh-my-openagent / oh-my-opencode, .json / .jsonc)
OMO_FILE=""
for f in "$OC_DIR"/oh-my-openagent.json "$OC_DIR"/oh-my-opencode.json \
         "$OC_DIR"/oh-my-openagent.jsonc "$OC_DIR"/oh-my-opencode.jsonc; do
    [ -f "$f" ] && { OMO_FILE="$f"; break; }
done

# ── 1. opencode.json: add Gemini provider ──
if [ ! -f "$OC_JSON" ]; then
    echo "[migration] v2: opencode.json not found — will be seeded on next container start."
else
    if jq -e '.provider.gemini' "$OC_JSON" > /dev/null 2>&1; then
        echo "[migration] v2: Gemini provider already present, skipping."
    else
        echo "[migration] v2: adding Gemini provider to opencode.json"
        jq '.provider.gemini = {
            "npm": "@ai-sdk/google",
            "name": "Google Gemini",
            "options": { "apiKey": "{env:GEMINI_API_KEY}" },
            "models": {
                "gemini-3.5-flash": {
                    "name": "Gemini 3.5 Flash",
                    "options": {}
                }
            }
        }' "$OC_JSON" > "$OC_JSON.tmp" && mv "$OC_JSON.tmp" "$OC_JSON"
    fi
fi

# ── 2. omo config: route multimodal-looker to Gemini ──
if [ -z "$OMO_FILE" ] || [ ! -f "$OMO_FILE" ]; then
    echo "[migration] v2: omo config not found — will be seeded on next container start."
else
    current_model=$(jq -r '.agents["multimodal-looker"].model // ""' "$OMO_FILE" 2>/dev/null || true)

    if [ "$current_model" = "gemini/gemini-3.5-flash" ]; then
        echo "[migration] v2: multimodal-looker already on Gemini, skipping."
    elif [ -n "$current_model" ]; then
        echo "[migration] v2: routing multimodal-looker to Gemini (was: $current_model)"
        jq '.agents["multimodal-looker"].model = "gemini/gemini-3.5-flash"' \
            "$OMO_FILE" > "$OMO_FILE.tmp" && mv "$OMO_FILE.tmp" "$OMO_FILE"

        if jq -e '.categories["multimodal-looker"]' "$OMO_FILE" > /dev/null 2>&1; then
            jq '.categories["multimodal-looker"].model = "gemini/gemini-3.5-flash"' \
                "$OMO_FILE" > "$OMO_FILE.tmp" && mv "$OMO_FILE.tmp" "$OMO_FILE"
        fi
    else
        echo "[migration] v2: multimodal-looker agent not found, skipping."
    fi
fi

echo "[migration] v2: done."
