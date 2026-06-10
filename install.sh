#!/usr/bin/env bash
# Install Claude Code statusline for Mac / Linux
# Run from the repo root: bash install.sh
# Copies statusline.sh + statusline.ini to ~/.claude/statusline/
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

FILES=("statusline.sh" "statusline.ini")

for f in "${FILES[@]}"; do
    if [[ -f "${SCRIPT_DIR}/${f}" ]]; then
        cp "${SCRIPT_DIR}/${f}" "$TARGET_DIR"
        echo "  OK: $f"
    else
        echo "  WARN: $f not found in repo — skipping"
    fi
done

chmod +x "${TARGET_DIR}/statusline.sh" 2>/dev/null || true
echo "  +x: statusline.sh"

echo
echo "Make sure your settings.json has the statusLine config:"
echo '  "statusLine": {'
echo '    "type": "command",'
echo '    "command": "$HOME/.claude/statusline/statusline.sh",'
echo '    "padding": 0'
echo '  }'

# -------------------------------------------
# Step 2: Migrate state files to subdirectory
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
