# Changelog

## [Unreleased]

### Added
- Strip `[1m]`/`[1M]` context suffix from model names before matching — third-party API providers append this suffix to indicate 1M context window, which previously broke INI pricing section matching and model beautification

## [2026-06-05]

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
