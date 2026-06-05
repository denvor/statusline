#!/usr/bin/env bash
# Claude Code Status Line (bash/jq)
# Displays: project name | model name | context usage bar | cost
# Dependencies: jq, git (optional)
set -euo pipefail

# Check jq availability
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

# Validate JSON
if ! echo "$raw_json" | jq empty 2>/dev/null; then
    echo "Claude Code"
    exit 0
fi

# ── 2. Extract fields with jq ────────────────────────────────────────
project_name=$(echo "$raw_json" | jq -r '
    ( .workspace.project_dir // .cwd // "" | split("/") | .[-1] // "" )
    // .workspace.repo.name // "..."
')
[ -z "$project_name" ] && project_name="..."

model_raw=$(echo "$raw_json" | jq -r '.model.display_name // "Unknown"')
# Strip [1m] / [1M] context suffix added by third-party API providers
model_clean=$(echo "$model_raw" | sed -E 's/\s*\[1[mi]\]$//')

context_pct=$(echo "$raw_json" | jq -r '.context_window.used_percentage // 0')
context_pct=$(awk -v p="$context_pct" 'BEGIN { printf "%d", p }')
context_size=$(echo "$raw_json" | jq -r '.context_window.context_window_size // 200000')

input_tokens=$(echo "$raw_json" | jq -r '.context_window.total_input_tokens // 0')
output_tokens=$(echo "$raw_json" | jq -r '.context_window.total_output_tokens // 0')

cur_in=$(echo "$raw_json" | jq -r '.context_window.current_usage.input_tokens // 0')
cur_out=$(echo "$raw_json" | jq -r '.context_window.current_usage.output_tokens // 0')
cur_cw=$(echo "$raw_json" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cur_cr=$(echo "$raw_json" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

session_id=$(echo "$raw_json" | jq -r '.session_id // "unknown"')

duration_ms=$(echo "$raw_json" | jq -r '.cost.total_duration_ms // 0')
cc_cost=$(echo "$raw_json" | jq -r '.cost.total_cost_usd // 0')

# Worktree
is_worktree=$(echo "$raw_json" | jq -r '(.worktree.name // "") + (.workspace.git_worktree // "")')
[ -n "$is_worktree" ] && is_worktree=1 || is_worktree=0

# Git branch
git_branch=""
repo_host=""
repo_host_raw=$(echo "$raw_json" | jq -r '.workspace.repo.host // ""')
if [ -n "$repo_host_raw" ]; then
    repo_host=$(echo "$repo_host_raw" | sed 's/\.com$//;s/\.org$//')
fi
project_dir=$(echo "$raw_json" | jq -r '.workspace.project_dir // .cwd // ""')
if [ -n "$project_dir" ] && command -v git &>/dev/null; then
    branch=$(git -C "$project_dir" branch --show-current 2>/dev/null) || true
    if [ -n "$branch" ]; then
        git_branch=$(echo "$branch" | tr -d '[:space:]')
    fi
fi

# Effort
effort_level=$(echo "$raw_json" | jq -r '.effort.level // ""')

# Thinking mode
thinking_enabled=$(echo "$raw_json" | jq -r '.thinking.enabled // false')

# ── 3. Model name beautify ───────────────────────────────────────────
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

# ── 4. Read INI pricing ──────────────────────────────────────────────
script_dir="${HOME}"
ini_path="${HOME}/.claude/statusline.ini"
state_path="${HOME}/.claude/statusline_state.json"

# Default pricing
input_price=2.00
output_price=8.00
cache_write_price=2.00
cache_read_price=0.50
currency="CNY"

# Parse INI: extract section matching $model_clean, fallback to default
if [ -f "$ini_path" ]; then
    # Try specific model section first, then default
    for section in "$model_clean" "default"; do
        section_data=$(awk -v sec="[$section]" '
            BEGIN { found=0 }
            $0 == sec   { found=1; next }
            /^\[/       { found=0 }
            found && /^[^#;]/ && /=/ { print }
        ' "$ini_path" 2>/dev/null)

        if [ -n "$section_data" ]; then
            while IFS='=' read -r key val; do
                key=$(echo "$key" | xargs)
                val=$(echo "$val" | xargs)
                case "$key" in
                    input_price)       input_price="$val" ;;
                    output_price)      output_price="$val" ;;
                    cache_write_price) cache_write_price="$val" ;;
                    cache_read_price)  cache_read_price="$val" ;;
                    currency)          currency=$(echo "$val" | tr '[:lower:]' '[:upper:]') ;;
                esac
            done <<< "$section_data"
            break
        fi
    done
fi

# Currency symbol
if [ "$currency" = "CNY" ]; then
    currency_symbol="¥"
else
    currency_symbol='$'
fi

# ── 5. Token accumulation with dedup ─────────────────────────────────

# Project key for per-project tracking
project_key=$(echo "$raw_json" | jq -r '.workspace.project_dir // .cwd // "unknown"')

cum_in=0; cum_out=0; cum_cw=0; cum_cr=0
ses_in=0; ses_out=0; ses_cw=0; ses_cr=0

# Read existing state and look up current project
if [ -f "$state_path" ]; then
    proj_state=$(jq -r --arg pk "$project_key" '.projects[$pk] // empty' "$state_path" 2>/dev/null)
else
    proj_state=""
fi

if [ -z "$proj_state" ]; then
    is_new_project=1
    is_new_session=1
else
    is_new_project=0
    proj_session=$(echo "$proj_state" | jq -r '.session_id // ""')
    if [ "$session_id" != "unknown" ] && [ "$proj_session" != "$session_id" ]; then
        is_new_session=1
    else
        is_new_session=0
    fi
fi

if [ "$is_new_project" -eq 1 ]; then
    cum_in=$cur_in; cum_out=$cur_out; cum_cw=$cur_cw; cum_cr=$cur_cr
    ses_in=$cur_in; ses_out=$cur_out; ses_cw=$cur_cw; ses_cr=$cur_cr
elif [ "$is_new_session" -eq 1 ]; then
    old_cum_in=$(echo "$proj_state" | jq -r '.cumulative_input // 0')
    old_cum_out=$(echo "$proj_state" | jq -r '.cumulative_output // 0')
    old_cum_cw=$(echo "$proj_state" | jq -r '.cumulative_cache_write // 0')
    old_cum_cr=$(echo "$proj_state" | jq -r '.cumulative_cache_read // 0')
    cum_in=$((old_cum_in + cur_in))
    cum_out=$((old_cum_out + cur_out))
    cum_cw=$((old_cum_cw + cur_cw))
    cum_cr=$((old_cum_cr + cur_cr))
    ses_in=$cur_in; ses_out=$cur_out; ses_cw=$cur_cw; ses_cr=$cur_cr
else
    last_in=$(echo "$proj_state" | jq -r '.last_input // 0')
    last_out=$(echo "$proj_state" | jq -r '.last_output // 0')
    last_cw=$(echo "$proj_state" | jq -r '.last_cache_write // 0')
    last_cr=$(echo "$proj_state" | jq -r '.last_cache_read // 0')

    if [ "$cur_in" = "$last_in" ] && [ "$cur_out" = "$last_out" ] && \
       [ "$cur_cw" = "$last_cw" ] && [ "$cur_cr" = "$last_cr" ]; then
        is_dup=1
    else
        is_dup=0
    fi

    cum_in=$(echo "$proj_state" | jq -r '.cumulative_input // 0')
    cum_out=$(echo "$proj_state" | jq -r '.cumulative_output // 0')
    cum_cw=$(echo "$proj_state" | jq -r '.cumulative_cache_write // 0')
    cum_cr=$(echo "$proj_state" | jq -r '.cumulative_cache_read // 0')
    ses_in=$(echo "$proj_state" | jq -r '.session_input // 0')
    ses_out=$(echo "$proj_state" | jq -r '.session_output // 0')
    ses_cw=$(echo "$proj_state" | jq -r '.session_cache_write // 0')
    ses_cr=$(echo "$proj_state" | jq -r '.session_cache_read // 0')

    total_cur=$((cur_in + cur_out + cur_cw + cur_cr))
    if [ "$is_dup" -eq 0 ] && [ "$total_cur" -gt 0 ]; then
        cum_in=$((cum_in + cur_in))
        cum_out=$((cum_out + cur_out))
        cum_cw=$((cum_cw + cur_cw))
        cum_cr=$((cum_cr + cur_cr))
        ses_in=$((ses_in + cur_in))
        ses_out=$((ses_out + cur_out))
        ses_cw=$((ses_cw + cur_cw))
        ses_cr=$((ses_cr + cur_cr))
    fi
fi

# Save state (rebuild full projects JSON)
if [ -f "$state_path" ]; then
    existing_projects=$(jq '.projects // {}' "$state_path" 2>/dev/null || echo "{}")
else
    existing_projects="{}"
fi

new_state=$(echo "$existing_projects" | jq --arg pk "$project_key" \
    --arg sid "$session_id" \
    --argjson si "$ses_in" --argjson so "$ses_out" --argjson scw "$ses_cw" --argjson scr "$ses_cr" \
    --argjson ci "$cum_in" --argjson co "$cum_out" --argjson ccw "$cum_cw" --argjson ccr "$cum_cr" \
    --argjson li "$cur_in" --argjson lo "$cur_out" --argjson lcw "$cur_cw" --argjson lcr "$cur_cr" \
    '.[$pk] = {
        session_id: $sid,
        session_input: $si, session_output: $so, session_cache_write: $scw, session_cache_read: $scr,
        cumulative_input: $ci, cumulative_output: $co, cumulative_cache_write: $ccw, cumulative_cache_read: $ccr,
        last_input: $li, last_output: $lo, last_cache_write: $lcw, last_cache_read: $lcr
    }' | jq '{projects: .}')
echo "$new_state" > "$state_path"

# ── 6. Calculate cost ────────────────────────────────────────────────
calc_cost() {
    awk -v ci="$1" -v co="$2" -v cw="$3" -v cr="$4" \
        -v ip="$input_price" -v op="$output_price" -v cwp="$cache_write_price" -v crp="$cache_read_price" \
        'BEGIN {
            total = (ci/1000000)*ip + (co/1000000)*op + (cw/1000000)*cwp + (cr/1000000)*crp;
            printf "%.6f", total
        }'
}

session_cost=$(calc_cost "$ses_in" "$ses_out" "$ses_cw" "$ses_cr")
cumulative_cost=$(calc_cost "$cum_in" "$cum_out" "$cum_cw" "$cum_cr")

# Fallback to Claude Code built-in cost
cum_is_zero=$(awk -v c="$cumulative_cost" 'BEGIN { print (c == 0.0) ? 1 : 0 }')
if [ "$cum_is_zero" -eq 1 ] && [ "$cc_cost" != "0" ] && [ -n "$cc_cost" ]; then
    cumulative_cost="$cc_cost"
fi

# ── 7. Duration formatting ───────────────────────────────────────────
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

# ── 8. Number formatting ─────────────────────────────────────────────
format_num() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        awk "BEGIN { printf \"%.1fM\", $n/1000000 }"
    elif [ "$n" -ge 1000 ]; then
        awk "BEGIN { printf \"%.1fK\", $n/1000 }"
    else
        echo "$n"
    fi
}

input_str=$(format_num "$input_tokens")
output_str=$(format_num "$output_tokens")
call_in_str=$(format_num "$cur_in")
call_out_str=$(format_num "$cur_out")
context_size_str=$(format_num "$context_size")

# ── 9. Icons ─────────────────────────────────────────────────────────
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
[ "$is_worktree" -eq 1 ] && project_icon="WT"

# ── 10. ANSI colors ──────────────────────────────────────────────────
e=$(printf '\033')
rst="${e}[0m"
bold="${e}[1m"
dim="${e}[2m"
cyan="${e}[36m"
green="${e}[32m"
blue="${e}[34m"
magenta="${e}[35m"
bcyan="${e}[96m"
bgreen="${e}[92m"
byellow="${e}[93m"
bred="${e}[91m"
bblue="${e}[94m"
bmagenta="${e}[95m"
bwhite="${e}[97m"

# ── 11. Progress bar (20 chars) ──────────────────────────────────────
bar_width=20
filled=$(( context_pct * bar_width / 100 ))
[ "$filled" -lt 0 ] && filled=0
[ "$context_pct" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
empty=$((bar_width - filled))

if [ "$context_pct" -gt 75 ]; then
    bar_color="$bred"; pct_color="$bred"
elif [ "$context_pct" -gt 50 ]; then
    bar_color="$byellow"; pct_color="$byellow"
else
    bar_color="$bgreen"; pct_color="$bgreen"
fi

bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '=')
bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '-')
bar="${bar_color}${bar_filled}${dim}${bar_empty}${rst}"

pct_str=$(printf '%3s' "$context_pct")

# Token color
if [ "$context_pct" -gt 75 ]; then
    token_color="$bred"
else
    token_color="$dim"
fi

# Cost color
cost_is_high=$(awk -v c="$cumulative_cost" -v s="$session_cost" 'BEGIN { print (c >= 1.0 || s >= 1.0) ? 1 : 0 }')
cost_is_mid=$(awk -v c="$cumulative_cost" -v s="$session_cost" 'BEGIN { print ((c >= 0.5 && c < 1.0) || (s >= 0.5 && s < 1.0)) ? 1 : 0 }')
if [ "$cost_is_high" -eq 1 ]; then
    cost_color="$bred"
elif [ "$cost_is_mid" -eq 1 ]; then
    cost_color="$byellow"
else
    cost_color="$bgreen"
fi

cost_str=$(printf '%s%.3f/%s%.3f' "$currency_symbol" "$session_cost" "$currency_symbol" "$cumulative_cost")

# ── 12. Build output line ────────────────────────────────────────────

# Default display order
display_order=("project" "model" "thinking" "effort" "bar" "ctx" "call" "git" "time" "cost")

# Override from INI [display] section
if [ -f "$ini_path" ]; then
    ini_order=$(awk '
        BEGIN { found=0 }
        /^\[display\]/ { found=1; next }
        /^\[/          { found=0 }
        found && /^[^#;]/ && /order/ { print; exit }
    ' "$ini_path" 2>/dev/null | sed 's/^[^=]*=\s*//;s/\s*$//')

    if [ -n "$ini_order" ]; then
        IFS=',' read -ra display_order <<< "$ini_order"
        for i in "${!display_order[@]}"; do
            display_order[$i]=$(echo "${display_order[$i]}" | xargs)
        done
    fi
fi

# Build field map
declare -A fields
fields[project]="${bold}${bcyan}[${project_icon}] ${project_name}${rst}"
fields[model]="${bmagenta}${model_display}${rst}"
[ -n "$thinking_icon" ] && fields[thinking]="${bcyan}${thinking_icon}${rst}" || fields[thinking]=""
[ -n "$effort_icon" ]   && fields[effort]="${byellow}${effort_icon}${rst}"      || fields[effort]=""
fields[bar]="${bar} ${bold}${pct_color}${pct_str}%${rst}"
fields[ctx]="ctx: ${bwhite}${input_str}/${output_str}${rst} ${dim}/${bold}${pct_color}${context_size_str}${rst}"
fields[call]="call: ${bwhite}i${rst}${bwhite}${call_in_str}${rst} ${bwhite}o${rst}${bwhite}${call_out_str}${rst}"

git_field=""
if [ -n "$git_branch" ]; then
    git_field="${cyan}git:${git_branch}${rst}"
    [ -n "$repo_host" ] && git_field="${git_field} ${dim}@${repo_host}${rst}"
fi
fields[git]="$git_field"

[ -n "$duration_str" ] && fields[time]="${bblue}time ${rst}${duration_str}" || fields[time]=""
fields[cost]="${bold}${cost_color}${cost_str}${rst}"

# Build line from display order
line=""
sep=" ${dim}|${rst} "
for key in "${display_order[@]}"; do
    val="${fields[$key]}"
    if [ -n "$val" ]; then
        [ -n "$line" ] && line+="$sep"
        line+="$val"
    fi
done

# ── 13. Output ───────────────────────────────────────────────────────
printf '%s\n' "$line"
exit 0
