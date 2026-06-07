# Claude Code Status Line

[![zh-CN](https://img.shields.io/badge/语言-中文-blue.svg)](README_zh.md)

A PowerShell / bash custom status line for [Claude Code](https://code.claude.com/docs/en/overview), designed for users of **third-party API providers** (DeepSeek, etc.). Displays project, model, context usage, token consumption, and **custom-priced cost** — all in a single line at the bottom of your terminal.

## Preview

> **Note:** The output uses ANSI color codes that render directly in your terminal. What you see below is the **rendered visual effect** — not raw text.

```
┌─ Status bar (bottom of Claude Code) ─────────────────────────────────────────────┐
│ [PR] hello │ DeepSeek V4 Pro T H │ ========------------ 42% │ ctx: 18.5K/3.2K     │
│ /200K │ call: i5K o1.2K @github │ time 5m │ ¥0.004/¥0.009                       │
└──────────────────────────────────────────────────────────────────────────────────┘
```

Each segment is color-coded for quick scanning:

| Segment | Example | Color |
|---------|---------|-------|
| Project | `[PR] hello` | Cyan bold |
| Model | `DeepSeek V4 Pro` | Magenta |
| Thinking | `T` | Cyan |
| Effort | `H` | Yellow |
| Context bar | `========------------` | Green → Yellow → Red as usage grows |
| Context % | `42%` | Same as bar, bold |
| Context occupancy + limit | `ctx: 18.5K/3.2K /200K` | Bright white + bar color |
| Per-call tokens | `call: i5K o1.2K` | Bright white |
| Git info | `git:main @github` | Cyan |
| Session time | `time 5m` | Blue |
| Session / project cost | `¥0.004/¥0.009` | Green → Yellow → Red with thresholds |

## Features

- **Project name** — auto-detected from working directory
- **Model display** — beautified names for DeepSeek & Claude model families
- **Context progress bar** — 20-char bar, color shifts green → yellow → red at 50% and 75%
- **Token details** — context window occupancy (`ctx:`) and per-call usage (`call:`)
- **Custom pricing** — read from `statusline.ini`, independent prices for input / output / cache writes / cache reads
- **Configurable display** — show/hide and reorder fields via `[display]` section in `statusline.ini` (10 fields available)
- **Multi-currency** — `¥` (CNY) or `$` (USD)
- **Per-project cost tracking** — costs tracked independently per project directory, stored in separate `statusline_state_<project>.json` files
- **Session + project cost split** — displays `session_cost/project_cost`; session resets on new Claude Code session, project cost persists
- **Debounce-safe** — detects and skips duplicate updates from Claude Code's 300ms debounce
- **Git info** — branch name + remote host (e.g., `@github`)
- **Worktree aware** — shows `[WT]` prefix inside git worktrees
- **Session duration** — displays elapsed time (e.g., `time 5m`), from `cost.total_duration_ms`
- **Zero dependencies** — pure PowerShell, no `jq` or Node.js required

## Requirements

- **Windows**: PowerShell 5.1+
- **Mac / Linux**: bash 3.2+, [jq](https://jqlang.github.io/jq/) (`brew install jq` / `apt install jq`)
- [Claude Code](https://code.claude.com/docs/en/overview) v2.1.90+

## Quick Start

### 1. Run the install script

From the repo root:

**Windows:**
```powershell
powershell -File install.ps1
```

**Mac / Linux:**
```bash
bash install.sh
```

This copies the required files to `~/.claude/` and migrates any old shared state file to the new per-project format.

### 2. Configure Claude Code

Add the following `"statusLine"` key to your **existing** `~/.claude/settings.json` (all projects) or `.claude/settings.json` (current project only). Do NOT replace the entire file — merge it alongside your other settings:

**Windows:**
```jsonc
"statusLine": {
  "type": "command",
  "command": "powershell.exe -NoProfile -File \"C:/Users/your-username/.claude/statusline.ps1\"",
  "padding": 0
}
```

**Mac / Linux:**
```jsonc
"statusLine": {
  "type": "command",
  "command": "$HOME/.claude/statusline.sh",
  "padding": 0
}
```

Replace `your-username` (Windows) with your actual username.

### 3. Set your pricing

Edit `statusline.ini`:

```ini
# Default pricing — used when no model-specific section matches
[default]
input_price=3.00
output_price=6.00
cache_write_price=3.00
cache_read_price=0.025
currency=CNY

# Model-specific pricing — matched by Claude Code model ID
[deepseek-v4-pro]
input_price=3.00
output_price=6.00
cache_write_price=3.00
cache_read_price=0.025
currency=CNY
```

- `currency=CNY` → `¥` symbol
- `currency=USD` → `$` symbol
- Pricing is matched by `[model_id]` section — the script looks up the current model automatically
- Falls back to `[default]` when no specific section matches

### 4. Send any message in Claude Code

The status bar appears at the bottom after the first interaction.

## Configuration Reference

### `statusline.ini`

Pricing is configured per-model via section headers. The section name must match the exact `model.display_name` value passed by Claude Code (e.g., `deepseek-v4-pro`).

> **Third-party API note:** Some providers append a `[1m]` or `[1M]` suffix to indicate a 1M context window. The script strips this suffix before matching, so the INI section should use the base model name (e.g., `[deepseek-v4-pro]`, not `[deepseek-v4-pro [1m]]`).

| Key | Description | Default |
|-----|-------------|---------|
| `[default]` | Fallback pricing when no model section matches | — |
| `input_price` | Price per 1M input tokens | `3.00` |
| `output_price` | Price per 1M output tokens | `6.00` |
| `cache_write_price` | Price per 1M cache-write tokens | `3.00` |
| `cache_read_price` | Price per 1M cache-read tokens | `0.025` |
| `currency` | Display currency: `CNY` or `USD` | `CNY` |

Each `[model_id]` section can independently configure the 5 keys above. If the INI file is missing, hardcoded defaults are used.

### `[display]` section

Controls which fields appear in the status line and in what order:

```ini
[display]
# Available fields: project, model, thinking, effort, bar, ctx, call, git, time, cost
order = project, model, thinking, effort, bar, ctx, call, git, time, cost
```

| Key | Description | Default |
|-----|-------------|---------|
| `order` | Comma-separated list of field names in display order | All 10 fields |

Fields not listed in `order` are hidden. The `\|` separator is inserted automatically between visible fields.

### Token types

| Token type | When charged |
|------------|-------------|
| Input | Every prompt sent to the model |
| Output | Every token generated by the model |
| Cache write | Tokens stored in Claude's prompt cache |
| Cache read | Tokens retrieved from cache (typically 1-25% of input price) |

## Output Layout

```
[icon] project │ Model │ T │ H │ ========------ 42% │ ctx: 18.5K/3.2K /200K │ call: i5K o1.2K │ git:main @github │ time 5m │ ¥0.004/¥0.009
  ①       ②    ③   ④             ⑤                         ⑥                  ⑦                  ⑧             ⑨            ⑩
```

| # | Field | Rendered as | Color |
|---|-------|------------|-------|
| ① | Project | `[PR] hello` | Cyan bold |
| ② | Model | `DeepSeek V4 Pro` | Magenta |
| ③ | Thinking | `T` | Cyan |
| ④ | Effort | `H` | Yellow |
| ⑤ | Progress bar + % | `========------------ 42%` | Green→Yellow→Red |
| ⑥ | Context occupancy + limit | `ctx: 18.5K/3.2K /200K` | Bright white + bar color |
| ⑦ | Per-call tokens | `call: i5K o1.2K` | Bright white |
| ⑧ | Git | `git:main @github` | Cyan |
| ⑨ | Session time | `time 5m` | Blue |
| ⑩ | Session / project cost | `¥0.004/¥0.009` | Green→Yellow→Red |

> **Icons:** `T` = extended thinking, `H`/`X`/`M`/`L`/`!` = effort level (high/xhigh/medium/low/max), `[WT]` = git worktree. Empty fields (e.g., no thinking, no git branch) are automatically hidden. Field order is controlled by `order` in `[display]`.

## How It Works

Claude Code pipes a JSON snapshot to the script via stdin after each assistant message. The script:

1. Parses the JSON (`ConvertFrom-Json`)
2. Extracts per-call token counts from `context_window.current_usage`
3. Reads/writes cumulative totals in `statusline_state_<project>.json` (one file per project, with per-session and cumulative tracking)
4. Loads pricing from `statusline.ini` (falls back to defaults if missing)
5. Computes cost: `sum(tokens / 1,000,000 × price_per_million)` across all four token types
6. Skips accumulation when `current_usage` is unchanged (debounce guard)
7. Outputs a single ANSI-colored line to stdout showing session cost / project cumulative cost

The state file tracks each project independently. New Claude Code sessions reset the session cost to zero while preserving the project cumulative cost.

## Files

| File | Role |
|------|------|
| `statusline.ps1` | Windows script — reads stdin, accumulates tokens, outputs status line |
| `statusline.sh` | Mac / Linux script — same functionality, uses jq for JSON parsing |
| `statusline.ini` | User-editable pricing configuration |
| `statusline_state_<project>.json` | Auto-generated — one per project, persists token counts (session + cumulative) |
| `install.ps1` / `install.sh` | Install scripts — copies files to `~/.claude/` and migrates old state files |

## FAQ

### How is the cost calculated?

The cost is based on **4 types of tokens × their respective unit prices**:

| Token type | Data source | INI key |
|-----------|-------------|---------|
| Input | `current_usage.input_tokens` | `input_price` |
| Output | `current_usage.output_tokens` | `output_price` |
| Cache write | `current_usage.cache_creation_input_tokens` | `cache_write_price` |
| Cache read | `current_usage.cache_read_input_tokens` | `cache_read_price` |

Formula: `Σ(cumulative_tokens / 1,000,000 × price_per_million)`

Unit prices are read from `statusline.ini`, matched by the current model's `[section]`, falling back to `[default]` if no match.

### Are tokens accumulated from the beginning of the project or just this session?

**Both are tracked.** The cost display shows `session_cost/project_cost`:

- **Session cost** (left of `/`): Resets to zero each time Claude Code starts a new session. Tracks only the current conversation.
- **Project cost** (right of `/`): Cumulative total for the project directory, persisting across sessions.

Token counts are tracked **per project directory** — different projects have independent counters, stored in separate `statusline_state_<project>.json` files.

### Why doesn't `claude -c` / `claude --continue` reset the session cost?

`claude --continue` (alias `-c`) preserves the same `session_id` as the previous conversation. The script detects "same session_id" and continues accumulating session tokens — it does **not** reset.

By contrast, `/resume` (the in-app slash command) assigns a **new** `session_id`, which triggers a session reset in the script.

**If you want a fresh session cost while still loading the previous conversation**, use:

```bash
claude --continue --fork-session
```

This creates a new `session_id` while loading the last conversation, so the script resets session cost to zero while keeping the project cumulative cost.

### What happens when I start a new session?

When Claude Code starts a session with a **new** `session_id` (different from what's stored in the state file), the script:

1. Detects `session_id` mismatch → new session
2. **Resets session counters** to zero (starts accumulating fresh)
3. **Preserves cumulative counters** (project total keeps growing)
4. Displays `new_session_cost / project_cumulative_cost`

This is the normal behavior for `claude` (fresh start), `claude --continue --fork-session`, and `/resume` — all of which assign a new `session_id`.

> If `statusline_state_<project>.json` is manually deleted or corrupted, accumulated history for that project is lost and counting restarts from zero.

## License

MIT
