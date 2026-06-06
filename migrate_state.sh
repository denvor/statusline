#!/usr/bin/env bash
# Migrate old statusline_state.json to per-project files
# Usage: bash migrate_state.sh [directory]
# Example: bash migrate_state.sh ~/.claude/
# Run from ~/.claude/ or pass the directory as argument
set -euo pipefail

DIR="${1:-$HOME/.claude}"
OLD_PATH="${DIR}/statusline_state.json"

if [[ ! -f "$OLD_PATH" ]]; then
    echo "No old state file found: $OLD_PATH"
    exit 0
fi

echo "Reading: $OLD_PATH"

# Check if jq is available
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed." >&2
    echo "Install it: brew install jq  /  apt install jq" >&2
    exit 1
fi

# Check if 'projects' key exists
if [[ "$(jq -r '.projects | type' "$OLD_PATH" 2>/dev/null)" != "object" ]]; then
    echo "No 'projects' key found — nothing to migrate."
    exit 0
fi

count=0
keys=$(jq -r '.projects | keys[]' "$OLD_PATH")

while IFS= read -r project_key; do
    # Replace path separator characters with underscore
    safe_name="statusline_state_$(echo "$project_key" | sed 's/[:\/\\]/_/g').json"
    new_path="${DIR}/${safe_name}"

    if [[ -f "$new_path" ]]; then
        echo "SKIP (already exists): $safe_name"
        continue
    fi

    # Extract project data and write to per-project file
    jq --arg key "$project_key" '.projects[$key]' "$OLD_PATH" > "$new_path"
    echo "OK: $safe_name"
    count=$((count + 1))
done <<< "$keys"

echo
echo "Migrated $count project(s)."
echo "Old file kept at: $OLD_PATH (delete manually if no longer needed)"
