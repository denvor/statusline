# Changelog

## [2026-06-07]

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
