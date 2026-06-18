# Changelog

## [2026-06-18]

### Added
- **statusline.sh + statusline.ps1** — Cumulative time tracking. Time display now shows `time Xm / YhZm` (session duration / project cumulative duration) instead of the previous single-message duration. New `session_duration_ms` and `cumulative_duration_ms` fields are persisted in per-project state files. Duration is computed as delta of the session-cumulative `total_duration_ms` to avoid double-counting on repeated invocations.

### Changed
- **README / FAQ** — Added "How to reset cumulative time / cumulative cost" section, covering full reset (delete state file) and partial reset (zero cumulative fields via jq).

### Fixed
- **statusline.sh** — `sync_jsonl_cost()` function definition moved before its call site. Bash executes scripts sequentially; the function was defined at line 329 but first called at line 254, so it was never found by the shell. This caused `jsonl_ever_scanned` to permanently remain `0`, blocking the three-value cost display. Combined with two other bugs below, the subagent cost tracking was effectively dead on Linux.
- **statusline.sh** — Awk variable name `sub` collides with the built-in `sub()` string function. Renamed to `sub_cost` to prevent silent awk syntax failure, which caused `jsonl_total_cost` and `sub_session_cost` to always display as `0.000`.
- **statusline.sh** — jq `// 0` alternative operator inside object value expressions with pipes (`{ key: [..] | add // 0 }`) requires parentheses on jq 1.7. Uncompilable expression silently failed under `2>/dev/null`, causing `sync_jsonl_cost` to never return real JSONL scan data.
- **statusline.sh + statusline.ps1** — `jsonl_ever_scanned` now unconditionally set to `true` after the first scan attempt, even when no JSONL files exist yet. Previously required non-empty scan results to flip the flag, which meant projects with zero subagent activity would never activate the three-value cost format.

## [2026-06-16]

### Added
- **Subagent cost tracking** — scans `~/.claude/projects/<project>/*.jsonl` for subagent API call usage, deduplicates by `(timestamp, input, output)` signature, and isolates per-session subagent cost via baseline snapshot at session start
- **JSONL scan interval** — configurable via `[jsonl]` section in `statusline.ini` (`sync_interval = N`, default 10, 0 to disable)
- **Three-value cost display** — `¥main / ¥subagent / ¥total` replaces the old two-value format when JSONL data is available; gracefully falls back to `¥session/¥cumulative` before the first scan completes
- **`jsonl_ever_scanned` state flag** — tracks whether a JSONL scan has ever completed, enabling accurate distinction between "not yet scanned" and "zero subagent cost"

### Fixed
- **statusline.ps1** — Inner guard (`$ji -eq 0 -and $jo -eq 0`) now also checks cache tokens (`$jcw_local`, `$jcr_local`) before skipping a JSONL entry, preventing cache-only assistant messages from being discarded
- **statusline.ps1** — Outer guard now checks `$jsonlTotalCW` and `$jsonlTotalCR` in addition to input/output totals, ensuring pure-cache scan results are saved to state
- **statusline.sh** — Removed basename fallback in `sync_jsonl_cost()` that could cause project directory name collision between projects with the same basename (now only uses the fully-sanitized path)
- **statusline.sh** — Added numeric validation for `sync_interval` INI value: non-digit values fall back to default 10, preventing `integer expression expected` bash errors
- **statusline.ps1 + statusline.sh** — Cost color threshold logic deduplicated: single color assignment after the if/else branch instead of duplicated logic in both branches
- **statusline.sh** — Three separate awk calls for `jsonl_session_cost`, `jsonl_total_cost`, and `sub_session_cost` merged into one awk call

## [2026-06-15]

### Changed
- **statusline.sh** — 19 individual jq calls consolidated into a single `jq @tsv` call (reduced from ~25+ subprocess forks per invocation to ~3-4)
- **statusline.sh** — Number formatting rewritten from awk to pure bash with nearest rounding (`format_num` function using integer arithmetic)
- **statusline.sh** — Cost calculation consolidated from 3 awk calls into 1
- **statusline.sh** — INI file read once into cached variable, parsed twice from memory instead of two disk reads
- **statusline.ps1** — INI dual-read merged into single pass; `$orderFromIni` captured during pricing parse
- **statusline.ps1** — Removed dead variables (`pctColor`, `tokenColor`, `$script_dir`)

### Fixed
- **statusline.sh** — `is_worktree` comparison broken after jq consolidation (`-eq 1` → `"true"` string comparison)
- **statusline.sh** — `format_num` rounding truncation → nearest rounding (1999 → 2.0K, not 1.9K)
- **statusline.ps1** — INI display order override never applied due to variable name conflict with default array
- **install.ps1** — Removed dead `$changed` variable and unreachable else branch; always writes settings.json

### Added
- Backup logic in both install scripts: `statusline.ini.bak` created before overwriting on reinstall
- README: `git clone` step in Quick Start; clarified that install script also modifies `settings.json`

### Added
- Install scripts (`install.ps1` / `install.sh`) with built-in old state migration — one-command setup that copies files to `~/.claude/` and migrates legacy `statusline_state.json`

### Removed
- Standalone migration scripts (`migrate_state.ps1` / `migrate_state.sh`) — merged into install scripts

## [2026-06-06]

### Added
- Per-project state files: each project gets its own `statusline_state_<project>.json` instead of sharing a single file — eliminates race condition when running multiple Claude Code sessions simultaneously (different projects could overwrite each other's state)

### Changed
- State file format: `{"projects": {"/path": {...}}}` → single-project JSON at `statusline_state_<project>.json` (no `projects` wrapper)

## [2026-06-05]

### Added
- Strip `[1m]`/`[1M]` context suffix from model names before matching — third-party API providers append this suffix to indicate 1M context window, which previously broke INI pricing section matching and model beautification

### Added
- Per-project cost tracking: costs tracked independently per project directory, stored in `statusline_state.json`
- Session/project cost split: displays `session_cost/project_cost` — session cost resets on new Claude Code session, project cumulative cost persists
- Configurable display: `[display]` section in `statusline.ini` controls which fields appear and their order (10 optional fields)

### Changed
- State file format: `{session_id, tokens}` per project → `{projects: {project_dir: {session_*, cumulative_*, session_id}}}`
- State JSON output: pretty-printed (multi-line, indented) instead of compressed single-line

## [2026-06-03]

### Fixed
- Fallback cost (`total_cost_usd`) now respects user-configured currency symbol instead of always forcing `$`
