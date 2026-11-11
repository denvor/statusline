# Claude Code Status Line

[![version](https://img.shields.io/badge/version-1.0.7-green.svg)](CHANGELOG.md) [![zh-CN](https://img.shields.io/badge/语言-中文-blue.svg)](README_zh.md)

A PowerShell / bash custom status line for [Claude Code](https://code.claude.com/docs/en/overview), designed for users of **third-party API providers** (DeepSeek, etc.). It reads the JSON snapshot Claude Code pipes to stdin and renders a single line at the bottom of your terminal: project, model, context usage, per-call tokens, and session time. No state files, no JSONL scanning, no pricing config.

> **Looking for cost tracking?** The full version `slineplus` adds per-project state files, per-model pricing, and subagent cost scanning — but it is **no longer maintained** (frequent model price changes). See [slineplus (full version, unmaintained)](#slineplus-full-version-unmaintained) at the bottom.

## Preview

> **Note:** The output uses ANSI color codes that render directly in your terminal. What you see below is the **rendered visual effect** — not raw text.

```
┌─ Status bar (bottom of Claude Code) ─────────────────────────────────────────────┐
│ [PR] hello │ DeepSeek V4 Pro T H │ ========------------ 42% │ ctx: 18.5K/3.2K     │
│ /200.0K │ call: i5.0K o1.2K │ git:main │ time 5m / 1h57m                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

Each segment is color-coded for quick scanning:

| Segment | Example | Color |
|---------|---------|-------|
| Project | `[PR] hello` | Cyan bold |
| Model | `DeepSeek V4 Pro` | Magenta |
| Thinking | `T` | Cyan |
| Effort | `H` | Bright yellow |
| Context bar | `========------------` | Green → Yellow → Red as usage grows |
| Context % | `42%` | Same as bar, bold |
| Context occupancy + limit | `ctx: 18.5K/3.2K /200.0K` | Bright white + bar color |
| Per-call tokens | `call: i5.0K o1.2K` | Bright white |
| Git branch | `git:main` | Cyan |
| Session time | `time 5m / 1h57m` | Blue |

## Features

- **Project name** — auto-detected from working directory
- **Model display** — beautified names for DeepSeek & Claude model families
- **Context progress bar** — 20-char bar, color shifts green → yellow → red at 50% and 75%
- **Token details** — context window occupancy (`ctx:`) and per-call usage (`call:`)
- **Configurable display** — show/hide and reorder fields via `[display]` section in `statusline.ini` (9 fields available)
- **Session time** — displays `time 5m / 1h57m` (active API time / wall-clock time), from `cost.total_api_duration_ms` and `cost.total_duration_ms` (see FAQ)
- **Per-session cache** — the last valid line is cached per `session_id` and re-emitted on intermediate frames, so `ctx:` never flashes to 0 while a response is streaming. After `/compact` the bar deliberately shows `0/0` until the first message following the compaction (see FAQ).
- **Git info** — branch name
- **Worktree aware** — shows `[WT]` prefix inside git worktrees
- **Zero dependencies (Windows)** — pure PowerShell, no `jq` or Node.js. Mac/Linux requires bash 3.2+ and `jq`.

## Requirements

- **Windows**: PowerShell 5.1+
- **Mac / Linux**: bash 3.2+, [jq](https://jqlang.github.io/jq/) (`brew install jq` / `apt install jq`)
- [Claude Code](https://code.claude.com/docs/en/overview) v2.1.90+

## Quick Start

### 0. Clone the repo

```bash
git clone https://github.com/denvor/statusline.git
cd statusline
```

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

This copies the script to `~/.claude/statusline/`.

### 2. The install script also modifies `settings.json`

The install script automatically adds a `statusLine` entry to `~/.claude/settings.json` — no manual editing needed.

### 3. Restart Claude Code and send any message

Restart Claude Code (or start a new session). The status bar appears at the bottom after the first interaction.

### 4. Configure displayed fields (optional)

Edit `~/.claude/statusline/statusline.ini` to choose which fields appear and in what order:

```ini
[display]
# Available fields: project, model, thinking, effort, bar, ctx, call, git, time
order = project, model, thinking, effort, bar, ctx, call, git, time
```

Fields not listed in `order` are hidden. The `|` separator is inserted automatically between visible fields.

## Configuration

### `statusline.ini`

The simplified version only reads the `[display]` section — no pricing configuration is needed.

| Key | Description | Default |
|-----|-------------|---------|
| `order` | Comma-separated list of field names in display order | All 9 fields |

## Output Layout

```
[icon] project │ Model │ T │ H │ ========------ 42% │ ctx: 18.5K/3.2K /200.0K │ call: i5.0K o1.2K │ git:main │ time 5m / 1h57m
  ①       ②    ③   ④             ⑤                         ⑥                  ⑦                ⑧          ⑨
```

| # | Field | Rendered as | Color |
|---|-------|------------|-------|
| ① | Project | `[PR] hello` | Cyan bold |
| ② | Model | `DeepSeek V4 Pro` | Magenta |
| ③ | Thinking | `T` | Cyan |
| ④ | Effort | `H` | Bright yellow |
| ⑤ | Progress bar + % | `========------------ 42%` | Green→Yellow→Red |
| ⑥ | Context occupancy + limit | `ctx: 18.5K/3.2K /200.0K` | Bright white + bar color |
| ⑦ | Per-call tokens | `call: i5.0K o1.2K` | Bright white |
| ⑧ | Git | `git:main` | Cyan |
| ⑨ | Session time | `time 5m / 1h57m` | Blue |

> **Icons:** `T` = extended thinking, `H`/`XH`/`M`/`L`/`X`/`U`/`A` = effort level (high/xhigh/medium/low/max/ultracode/auto), `[WT]` = git worktree. Empty fields (e.g., no thinking, no git branch) are automatically hidden. Field order is controlled by `order` in `[display]`.

## How It Works

Claude Code pipes a JSON snapshot to the script via stdin after each assistant message. The script:

1. Parses the JSON (`jq`)
2. Extracts per-call token counts from `context_window.current_usage`
3. Formats the context bar, token numbers, and session time
4. Falls back to the cached line when the frame carries no usable context data (streaming intermediate frames), so `ctx:` never flashes to 0
5. Outputs a single ANSI-colored line to stdout

The line is cached per `session_id` under the system temp dir (`/tmp/statusline/<session_id>`, Windows `%TEMP%\statusline`). No state files, no JSONL scanning.

## FAQ

### How is the time calculated? What do the two values mean?

**Two values are shown: `api / wall`.**

- **Left (API time)** — `cost.total_api_duration_ms`, which accumulates only the time spent waiting on API responses. Idle time, leaving the terminal open overnight, and machine sleep are all excluded.
- **Right (wall-clock time)** — `cost.total_duration_ms`, which is how long the session has been alive, idle time included.

Both fields are restored and continue accumulating when you resume a session with `claude -c` / `--resume`, so neither of them resets on resume. Only a brand-new session (new `session_id`) starts from zero, and `/clear` resets both.

Because the statusline is event-driven, the numbers only move when Claude Code re-runs the command, so they advance in jumps aligned with your messages rather than second by second.

### What does the context display show after `/compact`?

**It shows `0/0` (0%) until you send your next message.** That is intentional — the alternative is showing a stale pre-compact number, which is worse than an honest zero.

Why: Claude Code does not report the post-compact context in the statusline snapshot. Right after a compaction, every frame carries `context_window.total_input_tokens: 0` **and** `prompt_cache.recache_tokens_if_cold: null`, and the real value only comes back with the first assistant message after the compaction. The script distinguishes three frame types:

| Frame type | `total_input_tokens` | `recache_tokens_if_cold` | Display |
|---|---|---|---|
| Normal | `> 0` | same value | normal (`ctx: 18.5K/3.2K`) |
| Streaming intermediate | `0` | `> 0` | cached line — no 0 flash |
| After `/compact` | `0` | `null` | `0/0` (real value returns with the next message) |

Two things make the `0` look permanent:

1. **The statusline is event-driven.** Claude Code re-runs the command only when the snapshot changes — there is no timer unless you set `statusLine.refreshInterval` in `settings.json`. So nothing re-renders the bar while you sit idle after compacting.
2. **The `0` frame is not cached.** Writing it would overwrite the last good line, so the script renders it without updating the cache. The first real frame after your next message restores the true context immediately.

## slineplus (full version, unmaintained)

> ⚠️ **slineplus is no longer maintained.** Model prices change frequently, which makes its per-model accumulated cost tracking a maintenance burden. **We recommend the simplified `statusline` above** — it is actively maintained and covers project, model, context, and time display.

### What slineplus adds

- **Per-project state files** — `statusline_state_<project>.json`, one per project
- **Cumulative tracking** — session / cumulative token counts, durations, and costs
- **Custom pricing** — per-model prices from `statusline.ini`, input / output / cache writes / cache reads
- **Subagent cost scanning** — periodically reads `~/.claude/projects/<project>/*.jsonl` and prices subagent usage per model
- **Three-value cost display** — `session_cost / subagent_cost / project_cost`

### Install slineplus

**Windows:**
```powershell
powershell -File install_plus.ps1
```

**Mac / Linux:**
```bash
bash install_plus.sh
```

This copies `slineplus.ps1` / `slineplus.sh` to `~/.claude/statusline/`, migrates any existing `statusline_state_*.json` files, and points `settings.json` at the full version.

### Pricing configuration

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

```ini
[default]
input_price=3.00
output_price=6.00
cache_write_price=3.00
cache_read_price=0.025
currency=CNY

[deepseek-v4-pro]
input_price=3.00
output_price=6.00
cache_write_price=3.00
cache_read_price=0.025
currency=CNY
```

### `[jsonl]` section

Controls how often subagent cost data is scanned from JSONL files:

```ini
[jsonl]
# Scan every N statusline triggers (default: 10, set to 0 to disable)
sync_interval = 10
```

| Key | Description | Default |
|-----|-------------|---------|
| `sync_interval` | JSONL scan period (number of triggers between scans). Larger = less I/O, smaller = more responsive subagent updates | `10` |

> **Note:** JSONL scan reads all `*.jsonl` files in `~/.claude/projects/<project>/` recursively, parses `assistant`-type messages with `usage` data, and deduplicates by `(model, timestamp, input, output)`. At session start, a baseline snapshot is taken so only tokens consumed during the current session are attributed.

### Output layout

```
[icon] project │ Model │ T │ H │ ========------ 42% │ ctx: 18.5K/3.2K /200.0K │ call: i5.0K o1.2K │ git:main @github │ time 5m / 19h39m │ ¥0.004 / ¥0.001 / ¥0.009
```

| # | Field | Rendered as | Color |
|---|-------|------------|-------|
| ① | Project | `[PR] hello` | Cyan bold |
| ② | Model | `DeepSeek V4 Pro` | Magenta |
| ③ | Thinking | `T` | Cyan |
| ④ | Effort | `H` | Bright yellow |
| ⑤ | Progress bar + % | `========------------ 42%` | Green→Yellow→Red |
| ⑥ | Context occupancy + limit | `ctx: 18.5K/3.2K /200.0K` | Bright white + bar color |
| ⑦ | Per-call tokens | `call: i5.0K o1.2K` | Bright white |
| ⑧ | Git | `git:main @github` | Cyan |
| ⑨ | Session / cumulative time | `time 5m / 19h39m` | Blue |
| ⑩ | Session / subagent / project cost | `¥0.004 / ¥0.001 / ¥0.009` | Green→Yellow→Red |

### How it works

In addition to the simplified version's flow, slineplus:

1. Reads/writes cumulative totals in `statusline_state_<project>.json` (one file per project, with per-session and cumulative tracking). Costs are stored as computed values — each message is priced at its own model's INI rates and accumulated, not recomputed from raw tokens.
2. **Periodically scans `~/.claude/projects/<project>/*.jsonl`** for subagent API token usage, groups by the `model` field, prices each group at the model's INI rates, and accumulates into the project total. Session baseline isolates per-session subagent cost.
3. Loads pricing from `statusline.ini` for the current model (falls back to defaults if missing)
4. Skips accumulation when `current_usage` is unchanged (debounce guard)
5. Outputs session cost / subagent cost / project total cost, plus session duration / cumulative duration

The state file tracks each project independently. New Claude Code sessions reset the session cost to zero while preserving the project cumulative cost. Cumulative duration also persists across sessions.

### FAQ

#### How is the cost calculated?

The cost is based on **4 types of tokens × their respective unit prices**:

| Token type | Data source | INI key |
|-----------|-------------|---------|
| Input | `current_usage.input_tokens` | `input_price` |
| Output | `current_usage.output_tokens` | `output_price` |
| Cache write | `current_usage.cache_creation_input_tokens` | `cache_write_price` |
| Cache read | `current_usage.cache_read_input_tokens` | `cache_read_price` |

Formula: `Σ(cumulative_tokens / 1,000,000 × price_per_million)`

Unit prices are read from `statusline.ini`, matched by the current model's `[section]`, falling back to `[default]` if no match.

#### Are tokens accumulated from the beginning of the project or just this session?

**Both are tracked, at per-model pricing.** The cost display shows `session_cost / subagent_cost / project_cost`:

- **Session cost** (leftmost): Resets to zero each time Claude Code starts a new session. Each message is costed at its own model's INI prices and accumulated — switching models mid-session doesn't distort historical costs.
- **Subagent cost** (middle): Only the subagent consumption during the current session (computed as delta from baseline at session start). JSONL entries are grouped by `model` field and priced independently per model.
- **Project cost** (rightmost): Cumulative total for the project directory, persisting across sessions. Includes both main session and subagent costs, all priced at per-model rates. Switching API providers does not reset cumulative costs.

Token counts are tracked **per project directory** — different projects have independent counters, stored in separate `statusline_state_<project>.json` files.

#### Why doesn't `claude -c` / `claude --continue` reset the session cost?

`claude --continue` (alias `-c`) preserves the same `session_id` as the previous conversation. The script detects "same session_id" and continues accumulating session tokens — it does **not** reset.

By contrast, `/resume` (the in-app slash command) assigns a **new** `session_id`, which triggers a session reset in the script.

**If you want a fresh session cost while still loading the previous conversation**, use:

```bash
claude --continue --fork-session
```

This creates a new `session_id` while loading the last conversation, so the script resets session cost to zero while keeping the project cumulative cost.

#### How to reset cumulative time / cumulative cost?

To reset the project cumulative time (right side of `time XhYm`) and cumulative cost:

1. **Delete the state file** — fully resets all cumulative data (tokens, cost, duration):
   ```bash
   rm ~/.claude/statusline/statusline_state_<project>.json
   ```
   The script auto-recreates it on the next message, starting from zero.

2. **Partial reset** — zero out only cumulative fields while preserving the current session:
   ```bash
   # Use jq to reset cumulative values to current session values
   cat ~/.claude/statusline/statusline_state_<project>.json | jq '
     .cumulative_input = .session_input |
     .cumulative_output = .session_output |
     .cumulative_duration_ms = .session_duration_ms
   ' > /tmp/reset.json && mv /tmp/reset.json ~/.claude/statusline/statusline_state_<project>.json
   ```

> The `<project>` placeholder is the sanitized working directory path (e.g., `/home/user/work/my-project` → `_home_user_work_my-project`).

#### What happens when I start a new session?

When Claude Code starts a session with a **new** `session_id` (different from what's stored in the state file), the script:

1. Detects `session_id` mismatch → new session
2. **Resets session counters** to zero (starts accumulating fresh)
3. **Preserves cumulative counters** (project total keeps growing)
4. Displays `new_session_cost / project_cumulative_cost`

This is the normal behavior for `claude` (fresh start), `claude --continue --fork-session`, and `/resume` — all of which assign a new `session_id`.

> If `statusline_state_<project>.json` is manually deleted or corrupted, accumulated history for that project is lost and counting restarts from zero.

## License

MIT
