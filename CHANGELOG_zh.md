# 更新日志

## [Unreleased]

### Added
- 模型名称匹配前自动去除 `[1m]`/`[1M]` 上下文后缀 — 第三方 API 提供商会在模型名后追加此后缀表示 1M 上下文窗口，之前会导致 INI 定价段匹配和模型美化失败

## [2026-06-05]

### Added
- **按项目独立追踪费用**：不同项目目录的费用分别统计，存储在 `statusline_state.json`
- **会话/项目费用分离**：显示 `会话费用/项目累计费用`；新会话清零左侧，项目费用持续累加
- **可配置显示**：通过 `statusline.ini` 的 `[display]` 段控制显示哪些字段及顺序（共 10 个可选字段）

### Changed
- 状态文件格式：`{session_id, tokens}` → `{projects: {project_dir: {session_*, cumulative_*, session_id}}}`
- 状态 JSON 输出：改为格式化多行输出（而非压缩单行），便于阅读

## [2026-06-03]

### Fixed
- 回退费用（`total_cost_usd`）现在尊重用户配置的货币符号，不再强制显示 `$`
