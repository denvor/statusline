#!/usr/bin/env bash
# Install Claude Code statusline for Mac / Linux
# Run from the repo root: bash install.sh
# Copies statusline.sh + statusline.ini to ~/.claude/
# Migrates old statusline_state.json to per-project files if needed
set -euo pipefail

TARGET_DIR="${1:-$HOME/.claude}"
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
echo '    "command": "$HOME/.claude/statusline.sh",'
echo '    "padding": 0'
echo '  }'

# -------------------------------------------
# Step 2: Migrate old state file
# -------------------------------------------
OLD_PATH="${TARGET_DIR}/statusline_state.json"

if [[ ! -f "$OLD_PATH" ]]; then
    echo
    echo "No old state file to migrate."
    echo
    echo "Install complete!"
    exit 0
fi

echo
echo "--- Migrating old state file ---"
echo "Reading: $OLD_PATH"

# Check if jq is available
if ! command -v jq &>/dev/null; then
    echo "WARN: jq is required for migration but not installed."
    echo "Install it: brew install jq  /  apt install jq"
    echo "Skipping migration — you can run it later after installing jq."
    echo
    echo "Install complete!"
    exit 0
fi

# Check if 'projects' key exists
if [[ "$(jq -r '.projects | type' "$OLD_PATH" 2>/dev/null)" != "object" ]]; then
    echo "No 'projects' key found — nothing to migrate."
    echo
    echo "Install complete!"
    exit 0
fi

count=0
keys=$(jq -r '.projects | keys[]' "$OLD_PATH")

while IFS= read -r project_key; do
    safe_name="statusline_state_$(echo "$project_key" | sed 's/[:\/\\]/_/g').json"
    new_path="${TARGET_DIR}/${safe_name}"

    if [[ -f "$new_path" ]]; then
        echo "SKIP (already exists): $safe_name"
        continue
    fi

    jq --arg key "$project_key" '.projects[$key]' "$OLD_PATH" > "$new_path"
    echo "OK: $safe_name"
    count=$((count + 1))
done <<< "$keys"

echo
echo "Migrated $count project(s)."
echo "Old file kept at: $OLD_PATH (delete manually if no longer needed)"
echo
echo "Install complete!"
