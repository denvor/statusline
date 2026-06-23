#!/usr/bin/env bash
# statusline — Simplified stdin-only statusline
# Displays: project name | model | context usage bar | session time
# Dependencies: jq, git (optional)
set -euo pipefail

# Check jq
if ! command -v jq &>/dev/null; then
    echo "jq not found — install it: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

# ── 1. Read JSON from stdin ──────────────────────────────────────────
raw_json=$(cat 2>/dev/null) || true
if [ -z "$raw_json" ]; then
    echo "Claude Code"
    exit 0
fi
if ! echo "$raw_json" | jq empty 2>/dev/null; then
    echo "Claude Code"
    exit 0
fi

# ── 2. Extract fields with jq (single call) ──────────────────────────
IFS=$'\x1f' read -r project_name model_raw context_pct context_size \
    input_tokens output_tokens \
    cur_in cur_out duration_ms \
    is_worktree project_dir effort_level thinking_enabled \
    < <(echo "$raw_json" | jq -r '
    [
        ((.workspace.project_dir // .cwd // "" | split("/") | .[-1] // "") // .workspace.repo.name // "..."),
        (.model.display_name // "Unknown"),
        (.context_window.used_percentage // 0 | floor),
        (.context_window.context_window_size // 200000),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_output_tokens // 0),
        (.context_window.current_usage.input_tokens // 0),
        (.context_window.current_usage.output_tokens // 0),
        (.cost.total_duration_ms // 0),
        ((.worktree.name // "") + (.workspace.git_worktree // "") | length > 0),
        (.workspace.project_dir // .cwd // ""),
        (.effort.level // ""),
        (.thinking.enabled // false)
    ]
    | join("")')
[ -z "$project_name" ] && project_name="..."

# Strip [1m] / [1M] context suffix
model_clean=$(echo "$model_raw" | sed -E 's/\s*\[1[mM]\]$//')

# ── 3. Git branch ────────────────────────────────────────────────────
git_branch=""
if [ -n "$project_dir" ] && command -v git &>/dev/null; then
    branch=$(git -C "$project_dir" branch --show-current 2>/dev/null) || true
    [ -n "$branch" ] && git_branch=$(echo "$branch" | tr -d '[:space:]')
fi

# ── 4. Model name beautify ───────────────────────────────────────────
case "$model_clean" in
    deepseek-v4-pro)   model_display="DeepSeek V4 Pro" ;;
    deepseek-v4-flash)  model_display="DeepSeek V4 Flash" ;;
    deepseek*pro)       model_display="DeepSeek Pro" ;;
    deepseek*flash)     model_display="DeepSeek Flash" ;;
    claude-opus-4-8)    model_display="Opus 4.8" ;;
    claude-opus-4-7)    model_display="Opus 4.7" ;;
    claude-opus*)       model_display="Opus" ;;
    claude-sonnet-4-6)  model_display="Sonnet 4.6" ;;
    claude-sonnet-4-5)  model_display="Sonnet 4.5" ;;
    claude-sonnet*)     model_display="Sonnet" ;;
    claude-haiku*)      model_display="Haiku" ;;
    *)                  model_display="$model_clean" ;;
esac

# ── 5. Read INI display config ──────────────────────────────────────────
statusline_dir="${HOME}/.claude/statusline"
ini_path="${statusline_dir}/statusline.ini"

display_order=("project" "model" "thinking" "effort" "bar" "ctx" "call" "git" "time")

ini_content=""
[ -f "$ini_path" ] && ini_content=$(cat "$ini_path")

if [ -n "$ini_content" ]; then
    # Display order from [display] section
    ini_order=$(echo "$ini_content" | awk '
        BEGIN { found=0 }
        /^\[display\]/ { found=1; next }
        /^\[/          { found=0 }
        found && /^[^#;]/ && /order/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }
    ')
    if [ -n "$ini_order" ]; then
        IFS=',' read -ra display_order <<< "$ini_order"
        for i in "${!display_order[@]}"; do
            display_order[$i]=$(echo "${display_order[$i]}" | xargs)
        done
    fi
fi

# ── 6. Duration formatting ───────────────────────────────────────────
format_duration() {
    local ms=$1
    if [ -z "$ms" ] || [ "$ms" = "0" ] || [ "$ms" = "null" ]; then
        echo ""
        return
    fi
    local total_sec=$((ms / 1000))
    if [ "$total_sec" -lt 60 ]; then
        echo "${total_sec}s"
        return
    fi
    local min=$((total_sec / 60))
    if [ "$min" -lt 60 ]; then
        echo "${min}m"
        return
    fi
    local hr=$((min / 60))
    local rem=$((min % 60))
    echo "${hr}h${rem}m"
}
duration_str=$(format_duration "$duration_ms")

# ── 7. Number formatting ─────────────────────────────────────────────
format_num() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        local t=$(( (n * 10 + 500000) / 1000000 ))
        echo "$((t / 10)).$((t % 10))M"
    elif [ "$n" -ge 1000 ]; then
        local t=$(( (n * 10 + 500) / 1000 ))
        echo "$((t / 10)).$((t % 10))K"
    else
        echo "$n"
    fi
}

input_str=$(format_num "$input_tokens")
output_str=$(format_num "$output_tokens")
call_in_str=$(format_num "$cur_in")
call_out_str=$(format_num "$cur_out")
context_size_str=$(format_num "$context_size")

# ── 8. Icons ─────────────────────────────────────────────────────────
effort_icon=""
case "$effort_level" in
    xhigh) effort_icon="X" ;;
    high)  effort_icon="H" ;;
    medium) effort_icon="M" ;;
    low)   effort_icon="L" ;;
    max)   effort_icon="!" ;;
esac

thinking_icon=""
[ "$thinking_enabled" = "true" ] && thinking_icon="T"

project_icon="PR"
[ "$is_worktree" = "true" ] && project_icon="WT"

# ── 9. ANSI colors ──────────────────────────────────────────────────
e=$(printf '\033')
rst="${e}[0m"
bold="${e}[1m"
dim="${e}[2m"
cyan="${e}[36m"
green="${e}[32m"
magenta="${e}[35m"
bcyan="${e}[96m"
bgreen="${e}[92m"
byellow="${e}[93m"
bred="${e}[91m"
bblue="${e}[94m"
bmagenta="${e}[95m"
bwhite="${e}[97m"

# ── 10. Progress bar (20 chars) ──────────────────────────────────────
bar_width=20
filled=$(( context_pct * bar_width / 100 ))
[ "$filled" -lt 0 ] && filled=0
[ "$context_pct" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
empty=$((bar_width - filled))

if [ "$context_pct" -gt 75 ]; then
    bar_color="$bred"
elif [ "$context_pct" -gt 50 ]; then
    bar_color="$byellow"
else
    bar_color="$bgreen"
fi

bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '=')
bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '-')
bar="${bar_color}${bar_filled}${dim}${bar_empty}${rst}"
pct_str=$(printf '%3s' "$context_pct")

# ── 11. Build output line ────────────────────────────────────────────
declare -A fields
fields[project]="${bold}${bcyan}[${project_icon}] ${project_name}${rst}"
fields[model]="${bmagenta}${model_display}${rst}"
[ -n "$thinking_icon" ] && fields[thinking]="${bcyan}${thinking_icon}${rst}" || fields[thinking]=""
[ -n "$effort_icon" ]   && fields[effort]="${byellow}${effort_icon}${rst}"      || fields[effort]=""
fields[bar]="${bar} ${bold}${bar_color}${pct_str}%${rst}"
fields[ctx]="ctx: ${bwhite}${input_str}/${output_str}${rst} ${dim}/${bold}${bar_color}${context_size_str}${rst}"
fields[call]="call: ${bwhite}i${rst}${bwhite}${call_in_str}${rst} ${bwhite}o${rst}${bwhite}${call_out_str}${rst}"

git_field=""
if [ -n "$git_branch" ]; then
    git_field="${cyan}git:${git_branch}${rst}"
fi
fields[git]="$git_field"

[ -n "$duration_str" ] && fields[time]="${bblue}time ${rst}${duration_str}" || fields[time]=""
line=""
sep=" ${dim}|${rst} "
for key in "${display_order[@]}"; do
    val="${fields[$key]}"
    if [ -n "$val" ]; then
        [ -n "$line" ] && line+="$sep"
        line+="$val"
    fi
done

printf '%s\n' "$line"
exit 0
