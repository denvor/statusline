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

# ── 2. Extract fields with jq (single call, 1 fork vs 19) ────────────
IFS=$'\t' read -r project_name model_raw context_pct context_size \
    input_tokens output_tokens \
    cur_in cur_out cur_cw cur_cr session_id duration_ms cc_cost \
    is_worktree repo_host_raw project_dir effort_level thinking_enabled \
    project_key < <(echo "$raw_json" | jq -r '
    [
        ((.workspace.project_dir // .cwd // "" | split("/") | .[-1] // "") // .workspace.repo.name // "..."),
        (.model.display_name // "Unknown"),
        (.context_window.used_percentage // 0 | floor),
        (.context_window.context_window_size // 200000),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_output_tokens // 0),
        (.context_window.current_usage.input_tokens // 0),
        (.context_window.current_usage.output_tokens // 0),
        (.context_window.current_usage.cache_creation_input_tokens // 0),
        (.context_window.current_usage.cache_read_input_tokens // 0),
        (.session_id // "unknown"),
        (.cost.total_duration_ms // 0),
        (.cost.total_cost_usd // 0),
        ((.worktree.name // "") + (.workspace.git_worktree // "") | length > 0),
        (.workspace.repo.host // ""),
        (.workspace.project_dir // .cwd // ""),
        (.effort.level // ""),
        (.thinking.enabled // false),
        (.workspace.project_dir // .cwd // "unknown")
    ]
    | @tsv')
[ -z "$project_name" ] && project_name="..."
[ -z "$project_key" ] && project_key="unknown"

# Strip [1m] / [1M] context suffix added by third-party API providers
model_clean=$(echo "$model_raw" | sed -E 's/\s*\[1[mi]\]$//')

# Git repo host suffix strip
if [ -n "$repo_host_raw" ]; then
    repo_host=$(echo "$repo_host_raw" | sed 's/\.com$//;s/\.org$//')
fi

# Git branch
git_branch=""
if [ -n "$project_dir" ] && command -v git &>/dev/null; then
    branch=$(git -C "$project_dir" branch --show-current 2>/dev/null) || true
    if [ -n "$branch" ]; then
        git_branch=$(echo "$branch" | tr -d '[:space:]')
    fi
fi

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
statusline_dir="${HOME}/.claude/statusline"
ini_path="${statusline_dir}/statusline.ini"

# Default pricing
input_price=2.00
output_price=8.00
cache_write_price=2.00
cache_read_price=0.50
currency="CNY"

# Parse INI: extract section matching $model_clean, fallback to default
ini_content=""
[ -f "$ini_path" ] && ini_content=$(cat "$ini_path")

if [ -n "$ini_content" ]; then
    # Try specific model section first, then default
    for section in "$model_clean" "default"; do
        section_data=$(echo "$ini_content" | awk -v sec="[$section]" '
            BEGIN { found=0 }
            $0 == sec   { found=1; next }
            /^\[/       { found=0 }
            found && /^[^#;]/ && /=/ { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }
        ')

        if [ -n "$section_data" ]; then
            while IFS='=' read -r key val; do
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

# JSONL sync interval (from INI [jsonl] section, default 10)
jsonl_sync_interval=10
if [ -n "$ini_content" ]; then
    ini_interval=$(echo "$ini_content" | awk '
        BEGIN { found=0 }
        /^\[jsonl\]/ { found=1; next }
        /^\[/        { found=0 }
        found && /^[^#;]/ && /sync_interval/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }
    ')
    [ -n "$ini_interval" ] && jsonl_sync_interval="$ini_interval"
    # 校验：仅接受纯数字，否则回退默认值
    case "$jsonl_sync_interval" in
        ''|*[!0-9]*) jsonl_sync_interval=10;;
    esac
fi

# ── 5. Token accumulation with dedup ─────────────────────────────────

# Project key for per-project tracking (extracted in single jq call above)
safe_name=$(echo "$project_key" | sed 's/[:\/\\]/_/g')
state_path="${statusline_dir}/statusline_state_${safe_name}.json"

cum_in=0; cum_out=0; cum_cw=0; cum_cr=0
ses_in=0; ses_out=0; ses_cw=0; ses_cr=0
session_cost_stored=0; cumulative_cost_stored=0
jsonl_total_cost_stored=0; jsonl_total_cost_baseline=0

# Read existing state (per-project file, no projects wrapper)
if [ -f "$state_path" ]; then
    proj_state=$(cat "$state_path" 2>/dev/null)
else
    proj_state=""
fi

if [ -z "$proj_state" ]; then
    is_new_project=1
    is_new_session=1
    jsonl_input=0; jsonl_output=0; jsonl_cw=0; jsonl_cr=0; jsonl_scan_count=0
    jsonl_ever_scanned=0
    ses_dur_baseline=0
    session_cost_stored=0; cumulative_cost_stored=0
    jsonl_total_cost_stored=0; jsonl_total_cost_baseline=0
else
    is_new_project=0
    # Load cached JSONL scan results from state
    jsonl_input=$(echo "$proj_state" | jq -r '.jsonl_input // 0')
    jsonl_output=$(echo "$proj_state" | jq -r '.jsonl_output // 0')
    jsonl_cw=$(echo "$proj_state" | jq -r '.jsonl_cache_write // 0')
    jsonl_cr=$(echo "$proj_state" | jq -r '.jsonl_cache_read // 0')
    jsonl_scan_count=$(echo "$proj_state" | jq -r '.jsonl_scan_count // 0')
    jsonl_ever_scanned=$(echo "$proj_state" | jq -r '.jsonl_ever_scanned // 0')
    ses_dur=$(echo "$proj_state" | jq -r '.session_duration_ms // 0')
    cum_dur=$(echo "$proj_state" | jq -r '.cumulative_duration_ms // 0')
    ses_dur_baseline=$(echo "$proj_state" | jq -r '.session_duration_baseline // 0')
    session_cost_stored=$(echo "$proj_state" | jq -r '.session_cost_stored // 0')
    cumulative_cost_stored=$(echo "$proj_state" | jq -r '.cumulative_cost_stored // 0')
    jsonl_total_cost_stored=$(echo "$proj_state" | jq -r '.jsonl_total_cost_stored // 0')
    jsonl_total_cost_baseline=$(echo "$proj_state" | jq -r '.jsonl_total_cost_baseline // 0')
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
    ses_dur_baseline=$duration_ms; cum_dur=$duration_ms
    # Compute per-message cost using current model's prices
    read session_cost_stored cumulative_cost_stored <<< $(awk -v i="$cur_in" -v o="$cur_out" -v cw="$cur_cw" -v cr="$cur_cr" \
        -v ip="$input_price" -v op="$output_price" -v cwp="$cache_write_price" -v crp="$cache_read_price" \
        'BEGIN { c = (i/1000000)*ip + (o/1000000)*op + (cw/1000000)*cwp + (cr/1000000)*crp; printf "%.9f %.9f", c, c }')
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
    # New session: snapshot duration_ms as baseline, ses_dur starts from 0
    ses_dur_baseline=$duration_ms
    cum_dur=$((cum_dur + duration_ms))
    # New session: session cost reset to this message's cost (like ses_in)
    session_cost_stored=$(awk -v i="$cur_in" -v o="$cur_out" -v cw="$cur_cw" -v cr="$cur_cr" \
        -v ip="$input_price" -v op="$output_price" -v cwp="$cache_write_price" -v crp="$cache_read_price" \
        'BEGIN { printf "%.9f", (i/1000000)*ip + (o/1000000)*op + (cw/1000000)*cwp + (cr/1000000)*crp }')
    # cumulative_cost_stored preserved
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
    old_ses_dur=$(echo "$proj_state" | jq -r '.session_duration_ms // 0')
    cum_dur=$(echo "$proj_state" | jq -r '.cumulative_duration_ms // 0')

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
        # Incremental cost using current model's prices (per-message)
        read session_cost_stored cumulative_cost_stored <<< $(awk \
            -v sc="$session_cost_stored" -v cc="$cumulative_cost_stored" \
            -v i="$cur_in" -v o="$cur_out" -v cw="$cur_cw" -v cr="$cur_cr" \
            -v ip="$input_price" -v op="$output_price" -v cwp="$cache_write_price" -v crp="$cache_read_price" \
            'BEGIN {
                mc = (i/1000000)*ip + (o/1000000)*op + (cw/1000000)*cwp + (cr/1000000)*crp;
                printf "%.9f %.9f", sc + mc, cc + mc
            }')
        # duration_ms is session-cumulative: add only the delta since last recording
        old_raw_dur=$((ses_dur_baseline + old_ses_dur))
        dur_delta=$((duration_ms - old_raw_dur))
        if [ "$dur_delta" -lt 0 ]; then
            dur_delta=$duration_ms
        elif [ "$dur_delta" -gt 300000 ]; then
            # Gap > 5 min: likely session restart, reset baseline and skip gap
            ses_dur_baseline=$duration_ms
            dur_delta=0
        fi
        cum_dur=$((cum_dur + dur_delta))
    fi
fi

# ses_dur = duration_ms - baseline (0 at session start, grows during session)
ses_dur=$((duration_ms - ses_dur_baseline))
if [ "$ses_dur" -lt 0 ]; then
    ses_dur=0
elif [ "$ses_dur_baseline" -eq 0 ] && [ "$ses_dur" -gt 0 ] && [ "$is_new_project" -eq 0 ]; then
    # Migration: old state file had no baseline field (null → 0).
    # ses_dur loaded from state was the raw duration_ms from before the fix.
    # Reset baseline to current duration_ms so ses_dur starts fresh.
    ses_dur_baseline=$duration_ms
    ses_dur=0
fi

# Migration: seed stored costs from old state that lacked them
if [ "$is_new_project" -eq 0 ] && \
   [ "$(awk -v sc="$session_cost_stored" 'BEGIN { print (sc == 0.0) ? 1 : 0 }')" -eq 1 ] && \
   [ "$cumulative_input" -gt 0 ] && [ "$cumulative_output" -gt 0 ]; then
    read session_cost_stored cumulative_cost_stored <<< $(awk \
        -v si="$ses_in" -v so="$ses_out" -v scw="$ses_cw" -v scr="$ses_cr" \
        -v ci="$cum_in" -v co="$cum_out" -v ccw="$cum_cw" -v ccr="$cum_cr" \
        -v ip="$input_price" -v op="$output_price" -v cwp="$cache_write_price" -v crp="$cache_read_price" \
        'BEGIN {
            s = (si/1000000)*ip + (so/1000000)*op + (scw/1000000)*cwp + (scr/1000000)*crp;
            c = (ci/1000000)*ip + (co/1000000)*op + (ccw/1000000)*cwp + (ccr/1000000)*crp;
            printf "%.9f %.9f", s, c
        }')
fi

# New session: snapshot JSONL total cost as baseline for per-session subagent tracking
if [ "$is_new_session" -eq 1 ] && [ "$is_new_project" -eq 0 ]; then
    jsonl_total_cost_baseline=$jsonl_total_cost_stored
fi

# ── JSONL subagent cost scan ─────────────────────────────────
sync_jsonl_cost() {
    local project_dir="$1"
    local session_dir_name
    session_dir_name=$(echo "$project_dir" | sed 's/[:\/\\]/-/g')
    local target_dir="${HOME}/.claude/projects/${session_dir_name}"

    if [ ! -d "$target_dir" ]; then
        echo '{"total_cost":0}'
        return 0
    fi

    local result
    result=$(find "$target_dir" -name '*.jsonl' -type f -print0 2>/dev/null | \
        xargs -0 cat 2>/dev/null | \
        jq -s '
            [ .[] | select(.type == "assistant")
                  | select(.message.usage // empty | (.input_tokens // 0) + (.output_tokens // 0) > 0)
                  | { model: (.message.model // "unknown"), timestamp, usage: .message.usage }
            ] as $all
            | $all
            | unique_by("\(.model)|\(.timestamp)|\(.usage.input_tokens)|\(.usage.output_tokens)")
            | group_by(.model)
            | map({
                model: .[0].model,
                input: ([.[].usage.input_tokens] | add // 0),
                output: ([.[].usage.output_tokens] | add // 0),
                cw: ([.[].usage.cache_creation_input_tokens] | add // 0),
                cr: ([.[].usage.cache_read_input_tokens] | add // 0)
              })
        ' 2>/dev/null) || true

    if [ -z "$result" ] || [ "$result" = "null" ]; then
        echo '{"total_cost":0}'
        return 0
    fi

    # For each model group, look up INI prices and compute cost
    local total=0
    local models_count
    models_count=$(echo "$result" | jq 'length')
    for i in $(seq 0 $((models_count - 1))); do
        local model group_tokens
        group_tokens=$(echo "$result" | jq ".[$i]")
        local mod=$(echo "$group_tokens" | jq -r '.model')
        local grp_in=$(echo "$group_tokens" | jq -r '.input // 0')
        local grp_out=$(echo "$group_tokens" | jq -r '.output // 0')
        local grp_cw=$(echo "$group_tokens" | jq -r '.cw // 0')
        local grp_cr=$(echo "$group_tokens" | jq -r '.cr // 0')

        # Look up this model's pricing from INI
        local mp_ip=2.00 mp_op=8.00 mp_cwp=2.00 mp_crp=0.50
        if [ -n "$ini_content" ]; then
            local section_data
            section_data=$(echo "$ini_content" | awk -v sec="[$mod]" '
                BEGIN { found=0 }
                $0 == sec   { found=1; next }
                /^\[/       { found=0 }
                found && /^[^#;]/ && /=/ { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }
            ')
            if [ -z "$section_data" ]; then
                # Fallback to [default]
                section_data=$(echo "$ini_content" | awk -v sec="[default]" '
                    BEGIN { found=0 }
                    $0 == sec   { found=1; next }
                    /^\[/       { found=0 }
                    found && /^[^#;]/ && /=/ { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }
                ')
            fi
            if [ -n "$section_data" ]; then
                while IFS='=' read -r key val; do
                    case "$key" in
                        input_price)       mp_ip="$val" ;;
                        output_price)      mp_op="$val" ;;
                        cache_write_price) mp_cwp="$val" ;;
                        cache_read_price)  mp_crp="$val" ;;
                    esac
                done <<< "$section_data"
            fi
        fi

        local model_cost
        model_cost=$(awk -v i="$grp_in" -v o="$grp_out" -v cw="$grp_cw" -v cr="$grp_cr" \
            -v ip="$mp_ip" -v op="$mp_op" -v cwp="$mp_cwp" -v crp="$mp_crp" \
            'BEGIN { printf "%.9f", (i/1000000)*ip + (o/1000000)*op + (cw/1000000)*cwp + (cr/1000000)*crp }')
        total=$(awk -v a="$total" -v b="$model_cost" 'BEGIN { printf "%.9f", a + b }')
    done

    printf '{"total_cost":%.9f}' "$total"
}

# ── Periodic JSONL scan for subagent cost (every ~10 calls) ──
jsonl_scan_count=$((jsonl_scan_count + 1))
if [ "$jsonl_sync_interval" -gt 0 ] && [ "$jsonl_scan_count" -ge "$jsonl_sync_interval" ]; then
    jsonl_scan_count=0
    jsonl_result=$(sync_jsonl_cost "$project_key" 2>/dev/null) || true
    if [ -n "$jsonl_result" ]; then
        jsonl_scan_total=$(echo "$jsonl_result" | jq -r '.total_cost // 0')
        # Only update if scan cost >= current stored (monotonic safeguard)
        is_larger=$(awk -v new="$jsonl_scan_total" -v cur="$jsonl_total_cost_stored" \
            'BEGIN { print (new >= cur) ? 1 : 0 }')
        if [ "$is_larger" -eq 1 ]; then
            jsonl_total_cost_stored=$jsonl_scan_total
        fi
        jsonl_ever_scanned=1
    fi
fi

# Save state (single project per file)
new_state=$(jq -n \
    --arg sid "$session_id" \
    --argjson si "$ses_in" --argjson so "$ses_out" --argjson scw "$ses_cw" --argjson scr "$ses_cr" \
    --argjson ci "$cum_in" --argjson co "$cum_out" --argjson ccw "$cum_cw" --argjson ccr "$cum_cr" \
    --argjson li "$cur_in" --argjson lo "$cur_out" --argjson lcw "$cur_cw" --argjson lcr "$cur_cr" \
    --argjson ji "$jsonl_input" --argjson jo "$jsonl_output" --argjson jcw "$jsonl_cw" --argjson jcr "$jsonl_cr" \
    --argjson jsc "$jsonl_scan_count" \
    --argjson jes "$jsonl_ever_scanned" \
    --argjson sd "$ses_dur" --argjson cd "$cum_dur" \
    --argjson sdb "$ses_dur_baseline" \
    --argjson scs "$session_cost_stored" --argjson ccs "$cumulative_cost_stored" \
    --argjson jtc "$jsonl_total_cost_stored" --argjson jtb "$jsonl_total_cost_baseline" \
    '{
        session_id: $sid,
        session_input: $si, session_output: $so, session_cache_write: $scw, session_cache_read: $scr,
        cumulative_input: $ci, cumulative_output: $co, cumulative_cache_write: $ccw, cumulative_cache_read: $ccr,
        last_input: $li, last_output: $lo, last_cache_write: $lcw, last_cache_read: $lcr,
        jsonl_input: $ji, jsonl_output: $jo, jsonl_cache_write: $jcw, jsonl_cache_read: $jcr,
        jsonl_scan_count: $jsc,
        jsonl_ever_scanned: $jes,
        session_duration_ms: $sd, session_duration_baseline: $sdb, cumulative_duration_ms: $cd,
        session_cost_stored: $scs, cumulative_cost_stored: $ccs,
        jsonl_total_cost_stored: $jtc, jsonl_total_cost_baseline: $jtb
    }')
# Ensure statusline directory exists
mkdir -p "$statusline_dir" 2>/dev/null || true
echo "$new_state" > "$state_path"

# ── 6. Use stored costs (computed per-message at model's prices) ──
session_cost=$session_cost_stored
cumulative_cost=$cumulative_cost_stored

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
ses_dur_str=$(format_duration "$ses_dur")
cum_dur_str=$(format_duration "$cum_dur")
if [ -n "$ses_dur_str" ] && [ -n "$cum_dur_str" ]; then
    duration_str="${ses_dur_str} / ${cum_dur_str}"
elif [ -n "$ses_dur_str" ]; then
    duration_str="$ses_dur_str"
else
    duration_str=""
fi

# ── 8. Number formatting (pure bash, nearest rounding) ──────────────
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
[ "$is_worktree" = "true" ] && project_icon="WT"

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

# ── JSONL cost from stored values (per-model priced in scan) ──
jsonl_total_cost=$(awk -v v="$jsonl_total_cost_stored" 'BEGIN { printf "%.6f", v }')
jsonl_session_cost=$(awk -v cur="$jsonl_total_cost_stored" -v bl="$jsonl_total_cost_baseline" \
    'BEGIN { d = cur - bl; if (d < 0) d = 0; printf "%.6f", d }')
sub_session_cost=$(awk -v jsc="$jsonl_session_cost" -v sc="$session_cost" \
    'BEGIN { s = jsc - sc; if (s < 0) s = 0; printf "%.6f", s }')

if [ "$jsonl_ever_scanned" = "1" ]; then
    # 已扫描过，显示完整三值：主会话 / subagent / 项目总（含sub）
    cost_threshold="$jsonl_total_cost"
    cost_str=$(printf '%s%.3f / %s%.3f / %s%.3f' \
        "$currency_symbol" "$session_cost" \
        "$currency_symbol" "$sub_session_cost" \
        "$currency_symbol" "$jsonl_total_cost")
else
    # 尚未扫描，用旧两值格式
    cost_threshold=$(awk -v c="$cumulative_cost" -v s="$session_cost" \
        'BEGIN { if (c > s) print c; else print s }')
    cost_str=$(printf '%s%.3f/%s%.3f' \
        "$currency_symbol" "$session_cost" \
        "$currency_symbol" "$cumulative_cost")
fi
cost_color_code=$(awk -v v="$cost_threshold" \
    'BEGIN { if (v >= 1.0) print 2; else if (v >= 0.5) print 1; else print 0 }')
case "$cost_color_code" in
    2) cost_color="$bred" ;;
    1) cost_color="$byellow" ;;
    *) cost_color="$bgreen" ;;
esac

# ── 12. Build output line ────────────────────────────────────────────

# Default display order
display_order=("project" "model" "thinking" "effort" "bar" "ctx" "call" "git" "time" "cost")

# Override from INI [display] section (parsed from ini_content read above)
if [ -n "$ini_content" ]; then
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

# Build field map
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
    [ -n "$repo_host" ] && git_field="${git_field} ${dim}@${repo_host}${rst}"
fi
fields[git]="$git_field"

[ -n "$duration_str" ] && fields[time]="${bblue}time ${rst}${duration_str}" || fields[time]=""
fields[cost]="${bold}${cost_color}${cost_str}${rst}"

# Build field map

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
