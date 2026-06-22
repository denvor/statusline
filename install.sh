#!/usr/bin/env bash
# Install statusline — simplified stdin-only statusline for Linux / macOS
# Run: bash install.sh
# Copies statusline.sh to ~/.claude/statusline/ and updates settings.json
set -euo pipefail

TARGET_DIR="${HOME}/.claude/statusline"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------------------
# Step 1: Copy statusline.sh
# -------------------------------------------
if [[ ! -d "$TARGET_DIR" ]]; then
    mkdir -p "$TARGET_DIR"
    echo "Created: $TARGET_DIR"
fi

echo
echo "--- Installing to $TARGET_DIR ---"

if [[ -f "${SCRIPT_DIR}/statusline.sh" ]]; then
    cp "${SCRIPT_DIR}/statusline.sh" "$TARGET_DIR/"
    chmod +x "${TARGET_DIR}/statusline.sh"
    echo "  OK: statusline.sh"
else
    echo "  ERROR: statusline.sh not found in repo!"
    exit 1
fi

# statusline.ini is shared with slineplus — skip if already exists
if [[ -f "$TARGET_DIR/statusline.ini" ]]; then
    echo "  SKIP: statusline.ini (already exists)"
elif [[ -f "${SCRIPT_DIR}/statusline.ini" ]]; then
    cp "${SCRIPT_DIR}/statusline.ini" "$TARGET_DIR/"
    echo "  OK: statusline.ini"
else
    echo "  WARN: statusline.ini not found — statusline will use defaults"
fi

# -------------------------------------------
# Step 2: Configure settings.json
# -------------------------------------------
SETTINGS_PATH="${HOME}/.claude/settings.json"

echo
echo "--- Configuring settings.json ---"

if [[ -f "$SETTINGS_PATH" ]]; then
    new_settings=$(jq --arg cmd '$HOME/.claude/statusline/statusline.sh' \
        'del(.statusLine) | .statusLine = {"type":"command","command":$cmd,"padding":0}' \
        "$SETTINGS_PATH" 2>/dev/null) || true
    if [[ -n "$new_settings" ]]; then
        echo "$new_settings" > "$SETTINGS_PATH"
        echo "  Updated statusLine entry → statusline.sh"
    else
        echo "  WARN: Failed to update settings.json"
    fi
else
    jq -n --arg cmd '$HOME/.claude/statusline/statusline.sh' \
        '{"statusLine":{"type":"command","command":$cmd,"padding":0}}' > "$SETTINGS_PATH"
    echo "  Created: $SETTINGS_PATH"
fi

echo
echo "Install complete! Restart Claude Code to see statusline."
