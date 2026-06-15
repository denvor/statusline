# Changelog

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
