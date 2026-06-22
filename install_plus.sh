#!/usr/bin/env bash
# Install slineplus — full statusline with state files for Mac / Linux
# Run from the repo root: bash install_plus.sh
# Copies slineplus.sh + statusline.ini to ~/.claude/statusline/
# Migrates existing statusline_state_*.json files from ~/.claude/ to subdirectory
set -euo pipefail

TARGET_DIR="${1:-$HOME/.claude/statusline}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------------------
# Step 1: Copy files
# -------------------------------------------
if [[ ! -d "$TARGET_DIR" ]]; then
    mkdir -p "$TARGET_DIR"
    echo "Created: $TARGET_DIR"
fi

echo
echo "--- Installing to $TARGET_DIR ---"

FILES=("slineplus.sh" "statusline.ini")

for f in "${FILES[@]}"; do
    if [[ -f "${SCRIPT_DIR}/${f}" ]]; then
        # Back up existing ini before overwriting
        if [[ "$f" == "statusline.ini" && -f "$TARGET_DIR/$f" ]]; then
            cp "$TARGET_DIR/$f" "$TARGET_DIR/statusline.ini.bak"
            echo "  BACKUP: statusline.ini → statusline.ini.bak"
        fi
        cp "${SCRIPT_DIR}/${f}" "$TARGET_DIR"
        echo "  OK: $f"
    else
        echo "  WARN: $f not found in repo — skipping"
    fi
done

chmod +x "${TARGET_DIR}/slineplus.sh" 2>/dev/null || true
echo "  +x: slineplus.sh"

# -------------------------------------------
# Step 2: Configure settings.json
# -------------------------------------------
SETTINGS_PATH="${HOME}/.claude/settings.json"

echo
echo "--- Configuring settings.json ---"

if [[ -f "$SETTINGS_PATH" ]]; then
    # Remove old statusLine (if any) and add the new one in one jq pass
    # Use --arg to keep $HOME literal (Claude Code expands it at runtime)
    new_settings=$(jq --arg cmd '$HOME/.claude/statusline/slineplus.sh' \
        'del(.statusLine) | .statusLine = {"type":"command","command":$cmd,"padding":0}' \
        "$SETTINGS_PATH" 2>/dev/null) || true
    if [[ -n "$new_settings" ]]; then
        echo "$new_settings" > "$SETTINGS_PATH"
        echo "  Updated statusLine entry in: $SETTINGS_PATH"
    else
        echo "  WARN: Failed to update settings.json"
    fi
else
    # Create new settings.json with just statusLine
    jq -n --arg cmd '$HOME/.claude/statusline/slineplus.sh' \
        '{"statusLine":{"type":"command","command":$cmd,"padding":0}}' > "$SETTINGS_PATH"
    echo "  Created: $SETTINGS_PATH"
fi

# -------------------------------------------
# Step 3: Migrate state files to subdirectory
# -------------------------------------------
OLD_DIR="$HOME/.claude"
count=0
found=0

for f in "$OLD_DIR"/statusline_state_*.json; do
    # Skip if glob didn't match
    [ -f "$f" ] || continue
    found=1
    basename_f=$(basename "$f")
    dest="${TARGET_DIR}/${basename_f}"

    if [[ -f "$dest" ]]; then
        echo "  SKIP (already exists): $basename_f"
    else
        cp "$f" "$dest"
        echo "  OK: $basename_f"
        count=$((count + 1))
    fi
done

if [[ "$found" -eq 0 ]]; then
    echo
    echo "No state files to migrate."
else
    echo
    echo "Migrated $count state file(s)."
fi

echo
echo "Install complete!"
