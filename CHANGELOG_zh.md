# 更新日志

## [2026-06-18]

### Added
- **statusline.sh + statusline.ps1** — 累计时间追踪。时间显示改为 `time Xm / YhZm`（当前会话耗时 / 项目累计耗时），取代之前的单条消息耗时。状态文件新增 `session_duration_ms` 和 `cumulative_duration_ms` 字段。耗时按会话累计值 `total_duration_ms` 的增量计算，避免重复累加。
- **statusline.sh + statusline.ps1** — 按模型计费。费用不再从累计 token × 当前模型价格重算，而是每条消息用该消息的模型价格实时计算并累加到存储字段（`session_cost_stored` / `cumulative_cost_stored`）。JSONL 扫描按 `model` 分组，每组用对应模型定价算费。切换 API 不再导致历史费用归零。

### Changed
- **README / FAQ** — 新增「如何重置累计时间 / 累计费用」说明，包含删除状态文件（全量重置）和部分重置累计字段两种方式。

### Fixed
- **statusline.sh** — 将 `sync_jsonl_cost()` 函数定义移到调用之前。Bash 顺序执行脚本，函数定义在第 329 行但首次调用在第 254 行，导致函数从未被 shell 找到。`jsonl_ever_scanned` 永久为 `0`，三值费用显示被阻塞。加上下面两个 bug，Linux 上的 subagent 费用追踪实际上完全不可用。
- **statusline.sh** — Awk 变量名 `sub` 与内置函数 `sub()` 冲突。重命名为 `sub_cost` 避免 awk 静默语法错误，该错误导致 `jsonl_total_cost` 和 `sub_session_cost` 始终显示为 `0.000`。
- **statusline.sh** — jq 1.7 中，对象值表达式含有管道时 `// 0` 操作符需要加括号（`{ key: [..] | add // 0 }` 需改为 `{ key: ([..] | add // 0) }`）。无法编译的表达式在 `2>/dev/null` 下静默失败，`sync_jsonl_cost` 始终返回零值而非真实 JSONL 扫描数据。
- **statusline.sh + statusline.ps1** — `jsonl_ever_scanned` 现在在首次扫描尝试后无条件设为 `true`，即使 JSONL 文件不存在。此前需要非空扫描结果才能翻转标记，导致无 subagent 活动的项目永远不会激活三值费用格式。
- **statusline.sh + statusline.ps1** — 会话时间重置。新会话/重进时 `ses_dur` 从 `total_duration_ms - baseline` 计算，基线在会话启动时快照，使 session time 从 0 开始。旧状态文件无基线字段时自动推断。
- **statusline.sh + statusline.ps1** — 累计时间防暴涨。`dur_delta > 5 分钟` 判定为会话重启，跳过空档时间不累加到 `cum_dur`。
- **statusline.sh + statusline.ps1** — JSONL 扫描结果保护。切换 API 提供商时新 provider 无 JSONL 文件，扫描返回 0 不再覆盖已有累计值（仅增不降）。
- **statusline.sh** — 非 git 仓库崩溃。`git_branch` 变量未初始化导致 `set -u` 报错退出。改为声明时赋空值，非 git 仓库自动隐藏 git 字段。
- **statusline.sh** — 空 project_key。Claude Code JSON 中 `workspace.project_dir=""`（空字符串而非 null）时，jq 的 `// "unknown"` 不生效，导致状态文件路径为 `statusline_state_.json`，JSONL 扫描目标变为 `projects/` 根目录，累加全部项目的费用。添加 bash 守卫 `[ -z "$project_key" ] && project_key="unknown"`。
- **statusline.sh** — JSONL 扫描函数 `total_cost` 输出字符串而非数字，`--argjson` 拒绝接受，状态保存失败。改为 `printf '{"total_cost":%.9f}'`。

## [2026-06-16]

### Added
- **Subagent 费用追踪** — 扫描 `~/.claude/projects/<项目>/*.jsonl` 获取子 agent API 调用的 token 用量，通过 `(时间戳, input, output)` 签名去重，并通过会话启动时的基线快照隔离本次会话的 subagent 费用
- **JSONL 扫描间隔** — 可在 `statusline.ini` 的 `[jsonl]` 段中配置（`sync_interval = N`，默认 10，设为 0 可禁用）
- **三值费用显示** — 当 JSONL 数据可用时，`¥主会话 / ¥subagent / ¥总` 替代旧的两值格式；首次扫描完成前优雅回退到 `¥会话/¥累计`
- **`jsonl_ever_scanned` 状态标记** — 记录是否已完成至少一次 JSONL 扫描，精确区分"尚未扫描"和"子代理费用为零"

### Fixed
- **statusline.ps1** — 内层跳过守卫（`$ji -eq 0 -and $jo -eq 0`）新增检查 cache token（`$jcw_local`、`$jcr_local`），防止纯 cache 的 assistant 消息被丢弃
- **statusline.ps1** — 外层保存守卫新增 `$jsonlTotalCW` 和 `$jsonlTotalCR` 检查，确保纯 cache 扫描结果被保存到状态文件
- **statusline.sh** — 移除 `sync_jsonl_cost()` 中的 basename 回退逻辑，消除同名不同路径项目的目录碰撞风险（现仅使用完整路径脱敏后的目录名）
- **statusline.sh** — 对 `sync_interval` INI 值添加数字校验：非数字值回退默认值 10，防止 `integer expression expected` bash 错误
- **statusline.ps1 + statusline.sh** — 费用颜色阈值逻辑去重：if/else 分支后统一进行颜色赋值，而非在两个分支中重复
- **statusline.sh** — 将 `jsonl_session_cost`、`jsonl_total_cost`、`sub_session_cost` 三次独立 awk 调用合并为一次

## [2026-06-15]

### Changed
- **statusline.sh** — 19 次独立 jq 调用合并为单次 `jq @tsv` 调用（每次调用的子进程 fork 从 ~25+ 减少到 ~3-4）
- **statusline.sh** — 数字格式化从 awk 重写为纯 bash 邻近取整（`format_num` 函数使用整数运算）
- **statusline.sh** — 费用计算从 3 次 awk 调用合并为 1 次
- **statusline.sh** — INI 文件只读一次到缓存变量，从内存中解析两次代替两次磁盘读取
- **statusline.ps1** — INI 双次读取合并为一次遍历；`$orderFromIni` 在一次解析中捕获
- **statusline.ps1** — 移除死变量（`pctColor`、`tokenColor`、`$script_dir`）

### Fixed
- **statusline.sh** — jq 合并后 `is_worktree` 比较出错（`-eq 1` → `"true"` 字符串比较）
- **statusline.sh** — `format_num` 取整截断改为邻近取整（1999 → 2.0K，而非 1.9K）
- **statusline.ps1** — INI 显示顺序覆盖因变量名与默认数组冲突而从未生效
- **install.ps1** — 移除死变量 `$changed` 和不可达的 else 分支；始终写入 settings.json

### Added
- 两个安装脚本均添加备份逻辑：重新安装前将 `statusline.ini` 备份为 `statusline.ini.bak`
- README：快速开始增加 `git clone` 步骤；说明安装脚本也会修改 `settings.json`

## [2026-06-07]

### Added
- 安装脚本（`install.ps1` / `install.sh`）内建旧状态迁移 — 一键复制文件到 `~/.claude/` 并自动迁移旧版 `statusline_state.json`

### Removed
- 独立迁移脚本（`migrate_state.ps1` / `migrate_state.sh`）— 已合并到安装脚本中

## [2026-06-06]

### Added
- 按项目独立状态文件：每个项目使用独立的 `statusline_state_<项目>.json`，消除同时运行多个 Claude Code 会话时的竞态条件（不同项目会互相覆盖状态）

### Changed
- 状态文件格式：从 `{"projects": {"/path": {...}}}` 改为单项目 JSON `statusline_state_<项目>.json`（移除 `projects` 包装）

## [2026-06-05]

### Added
- 模型名称匹配前自动去除 `[1m]`/`[1M]` 上下文后缀 — 第三方 API 提供商会在模型名后追加此后缀表示 1M 上下文窗口，之前会导致 INI 定价段匹配和模型美化失败

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
