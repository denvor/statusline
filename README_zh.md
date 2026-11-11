# Claude Code 状态栏美化脚本

[![version](https://img.shields.io/badge/version-1.0.7-green.svg)](CHANGELOG_zh.md) [![en](https://img.shields.io/badge/lang-English-red.svg)](README.md)

基于 PowerShell / bash 的 [Claude Code](https://code.claude.com/docs/zh-CN/overview) 自定义状态栏，专为**第三方 API 用户**（如 DeepSeek）设计。它读取 Claude Code 通过 stdin 传入的 JSON 快照，在终端底部单行显示项目名、模型名、上下文用量、单次调用 Token 和会话时间。无状态文件、无 JSONL 扫描、无需配置定价。

> **需要费用统计？** 完整版 `slineplus` 提供按项目独立的状态文件、按模型定价和 subagent 费用扫描 —— 但它**不再维护**（模型价格变化频繁）。见底部 [slineplus（完整版，停止维护）](#slineplus完整版停止维护)。

## 效果预览

> **说明：** 输出使用 ANSI 颜色码，直接在终端渲染。下方展示的是**实际视觉效果**，非原始文本。

```
┌─ 状态栏（显示在 Claude Code 底部）─────────────────────────────────────────────────┐
│ [PR] hello │ DeepSeek V4 Pro T H │ ========------------ 42% │ ctx: 18.5K/3.2K     │
│ /200.0K │ call: i5.0K o1.2K │ git:main │ time 5m / 1h57m                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

各区域颜色区分，一目了然：

| 区域 | 示例 | 颜色 |
|------|------|------|
| 项目名 | `[PR] hello` | 青色粗体 |
| 模型 | `DeepSeek V4 Pro` | 洋红 |
| 思考模式 | `T` | 青色 |
| 推理强度 | `H` | 亮黄色 |
| 上下文进度条 | `========------------` | 绿 → 黄 → 红（随用量变化） |
| 百分比 | `42%` | 与进度条同色，粗体 |
| 上下文占用 + 上限 | `ctx: 18.5K/3.2K /200.0K` | 亮白色 + 进度条颜色 |
| 单次调用 | `call: i5.0K o1.2K` | 亮白色 |
| Git 分支 | `git:main` | 青色 |
| 会话时间 | `time 5m / 1h57m` | 蓝色 |

## 功能特性

- **项目名** — 自动从工作目录提取
- **模型显示** — 美化 DeepSeek、Claude 系列模型名称
- **上下文进度条** — 20 字符宽度，50%/75% 阈值切换绿/黄/红色
- **Token 详情** — 同时显示上下文窗口占用（`ctx:`）和最近一次调用用量（`call:`）
- **可配置显示** — 通过 `[display]` 段控制显示哪些字段及顺序（共 9 个可选字段）
- **会话时间** — 显示 `time 5m / 1h57m`（活跃 API 耗时 / 墙钟时间），数据来自 `cost.total_api_duration_ms` 和 `cost.total_duration_ms`（见常见问题）
- **按会话缓存** — 最后一次有效输出按 `session_id` 缓存，中间态帧直接复用，流式输出期间 `ctx:` 不会闪回 0。`/compact` 之后状态栏会刻意显示 `0/0`，直到 compact 后的第一条消息才恢复（见常见问题）
- **Git 信息** — 分支名
- **Worktree 感知** — git worktree 中显示 `[WT]` 前缀
- **零依赖（Windows）** — 纯 PowerShell，不需要 `jq` 或 Node.js。Mac/Linux 需要 bash 3.2+ 和 `jq`

## 环境要求

- **Windows**：PowerShell 5.1+
- **Mac / Linux**：bash 3.2+、[jq](https://jqlang.github.io/jq/)（`brew install jq` / `apt install jq`）
- [Claude Code](https://code.claude.com/docs/zh-CN/overview) v2.1.90+

## 快速开始

### 0. 克隆仓库

```bash
git clone https://github.com/denvor/statusline.git
cd statusline
```

### 1. 运行安装脚本

在仓库根目录执行：

**Windows：**
```powershell
powershell -File install.ps1
```

**Mac / Linux：**
```bash
bash install.sh
```

脚本会将状态栏脚本复制到 `~/.claude/statusline/`。

### 2. 安装脚本也会修改 `settings.json`

安装脚本会自动在 `~/.claude/settings.json` 中添加 `statusLine` 配置项，无需手动编辑。

### 3. 重启 Claude Code 并发送任意消息

重启 Claude Code（或启动新会话）。发送任意消息后底部即显示状态栏。

### 4. 配置显示字段（可选）

编辑 `~/.claude/statusline/statusline.ini`，选择要显示的字段及顺序：

```ini
[display]
# 可选字段: project, model, thinking, effort, bar, ctx, call, git, time
order = project, model, thinking, effort, bar, ctx, call, git, time
```

未在 `order` 中列出的字段会被隐藏。可见字段之间自动插入 `|` 分隔符。

## 配置说明

### `statusline.ini`

精简版只读取 `[display]` 段 —— 不需要配置定价。

| 键 | 说明 | 默认值 |
|----|------|--------|
| `order` | 逗号分隔的字段名列表，按此顺序显示 | 全部 9 个字段 |

## 输出布局

```
[图标] 项目名 │ 模型 │ T │ H │ ========------ 42% │ ctx: 18.5K/3.2K /200.0K │ call: i5.0K o1.2K │ git:main │ time 5m / 1h57m
  ①      ②    ③   ④             ⑤                         ⑥                  ⑦                ⑧          ⑨
```

| # | 字段 | 渲染效果 | 颜色 |
|---|------|---------|------|
| ① | 项目 | `[PR] hello` | 青色粗体 |
| ② | 模型 | `DeepSeek V4 Pro` | 洋红 |
| ③ | 思考模式 | `T` | 青色 |
| ④ | 推理强度 | `H` | 亮黄色 |
| ⑤ | 进度条 + 百分比 | `========------------ 42%` | 绿→黄→红 |
| ⑥ | 上下文占用 + 上限 | `ctx: 18.5K/3.2K /200.0K` | 亮白色 + 进度条颜色 |
| ⑦ | 单次调用 | `call: i5.0K o1.2K` | 亮白色 |
| ⑧ | Git | `git:main` | 青色 |
| ⑨ | 会话时间 | `time 5m / 1h57m` | 蓝色 |

> **图标说明：** `T` = 扩展思考已开启，`H`/`XH`/`M`/`L`/`X`/`U`/`A` = 推理强度（高/极高/中/低/最大/ultracode/自动），`[WT]` = 处于 git worktree 中。空字段（如无思考模式、无 git 分支）自动隐藏。字段顺序由 `[display]` 段的 `order` 控制。

## 工作原理

Claude Code 在每次助手消息后通过 stdin 向脚本传入 JSON 快照。脚本执行流程：

1. 解析 JSON（`jq`）
2. 从 `context_window.current_usage` 提取单次调用的 Token 数
3. 格式化上下文进度条、Token 数字和会话时间
4. 当帧内没有可用的上下文数据时（流式输出中间帧），复用缓存行，避免 `ctx:` 闪回 0
5. 输出一行 ANSI 彩色文本到 stdout

输出行按 `session_id` 缓存在系统临时目录（`/tmp/statusline/<session_id>`，Windows 为 `%TEMP%\statusline`）。无状态文件、无 JSONL 扫描。

## 常见问题

### 时间是如何计算的？两个值分别是什么？

**显示两个值：`API 时间 / 墙钟时间`。**

- **左（API 时间）** — `cost.total_api_duration_ms`，只累加等待 API 响应的时间。空闲、整晚挂着终端不动、机器睡眠都不计入。
- **右（墙钟时间）** — `cost.total_duration_ms`，会话从启动到现在的实际存活时长，含空闲。

用 `claude -c` / `--resume` 恢复会话时，两个字段都会恢复并继续累加，不会重置。只有全新会话（新 `session_id`）才从 0 开始，`/clear` 会将两者清零。

由于状态栏是事件驱动的，数字只在 Claude Code 重新运行时更新，所以它是随着你的消息跳跃式增长，而不是逐秒走动。

### `/compact` 之后上下文显示什么？

**显示 `0/0`（0%），直到你发送下一条消息。** 这是有意为之 —— 与其显示一个 compact 之前的陈旧数字，不如诚实地显示 0。

原因：Claude Code 不会在状态栏快照里上报 compact 后的上下文。compact 刚结束时，每一帧的 `context_window.total_input_tokens` 都是 `0`，而且 `prompt_cache.recache_tokens_if_cold` 是 `null`；真实数值要等 compact 之后的第一条助手消息才会回来。脚本据此区分三种帧：

| 帧类型 | `total_input_tokens` | `recache_tokens_if_cold` | 显示 |
|---|---|---|---|
| 正常 | `> 0` | 同值 | 正常（`ctx: 18.5K/3.2K`）|
| 流式中间帧 | `0` | `> 0` | 复用缓存行，不闪 0 |
| `/compact` 之后 | `0` | `null` | `0/0`（下一条消息后恢复真实值）|

有两个原因让这个 `0` 看起来一直是 0：

1. **状态栏是事件驱动的。** Claude Code 只在快照变化时重新执行状态栏命令 —— 除非你在 `settings.json` 里设置 `statusLine.refreshInterval`，否则没有定时器。所以 compact 后闲着不动时，状态栏不会重新渲染。
2. **这个 0 帧不会被写进缓存。** 写进去会覆盖掉最后一次有效行，所以脚本只渲染、不更新缓存。你下一条消息后的第一帧真实数据会立即恢复显示。

## slineplus（完整版，停止维护）

> ⚠️ **slineplus 不再维护。** 模型价格变化频繁，按模型累计的费用追踪维护成本过高。**建议使用上面的精简版 `statusline`** —— 它持续维护，覆盖项目名、模型、上下文和时间显示。

### slineplus 额外提供

- **按项目独立的状态文件** — `statusline_state_<项目>.json`，每个项目一个
- **累计追踪** — 会话 / 累计的 Token、耗时和费用
- **自定义定价** — 从 `statusline.ini` 按模型读取价格，输入 / 输出 / 缓存写入 / 缓存读取分别定价
- **Subagent 费用扫描** — 定期读取 `~/.claude/projects/<项目>/*.jsonl`，按模型为 subagent 用量计价
- **三值费用显示** — `会话费用 / subagent 费用 / 项目总费用`

### 安装 slineplus

**Windows：**
```powershell
powershell -File install_plus.ps1
```

**Mac / Linux：**
```bash
bash install_plus.sh
```

脚本会将 `slineplus.ps1` / `slineplus.sh` 复制到 `~/.claude/statusline/`，迁移已有的 `statusline_state_*.json` 状态文件，并把 `settings.json` 指向完整版。

### 定价配置

定价通过 `[模型ID]` 分段配置，脚本根据当前模型自动匹配。段名必须与 Claude Code 传入的 `model.display_name` 原始值完全一致（如 `deepseek-v4-pro`）。

> **第三方 API 注意：** 部分提供商会在模型名后追加 `[1m]` 或 `[1M]` 后缀表示 1M 上下文窗口。脚本在匹配前会自动去除此后缀，因此 INI 段应使用基础模型名（如 `[deepseek-v4-pro]`，而非 `[deepseek-v4-pro [1m]]`）。

| 键 | 说明 | 默认值 |
|----|------|--------|
| `[default]` | 未匹配到具体模型时的回退定价 | — |
| `input_price` | 每百万输入 Token 价格 | `3.00` |
| `output_price` | 每百万输出 Token 价格 | `6.00` |
| `cache_write_price` | 每百万缓存写入 Token 价格 | `3.00` |
| `cache_read_price` | 每百万缓存读取 Token 价格 | `0.025` |
| `currency` | 货币：`CNY` 或 `USD` | `CNY` |

每个 `[模型ID]` 段内可独立配置以上 5 个 key。如果 INI 文件缺失，使用硬编码默认值。

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

### `[jsonl]` 段

控制 JSONL 扫描 subagent 费用的频率：

```ini
[jsonl]
# 每 N 次 statusline 触发扫描一次（默认 10，设为 0 可禁用）
sync_interval = 10
```

| 键 | 说明 | 默认值 |
|----|------|--------|
| `sync_interval` | JSONL 扫描周期（两次扫描之间的触发次数）。增大值减少 I/O，减小值更快反映 subagent 费用 | `10` |

> **说明：** JSONL 扫描递归读取 `~/.claude/projects/<项目>/` 下所有 `*.jsonl` 文件，解析 `type == "assistant"` 且包含 `usage` 数据的消息，通过 `(模型, 时间戳, input, output)` 签名去重。会话启动时自动快照基线，确保只统计当前会话期间的 token 消耗。

### 输出布局

```
[图标] 项目名 │ 模型 │ T │ H │ ========------ 42% │ ctx: 18.5K/3.2K /200.0K │ call: i5.0K o1.2K │ git:main @github │ time 5m / 19h39m │ ¥0.004 / ¥0.001 / ¥0.009
```

| # | 字段 | 渲染效果 | 颜色 |
|---|------|---------|------|
| ① | 项目 | `[PR] hello` | 青色粗体 |
| ② | 模型 | `DeepSeek V4 Pro` | 洋红 |
| ③ | 思考模式 | `T` | 青色 |
| ④ | 推理强度 | `H` | 亮黄色 |
| ⑤ | 进度条 + 百分比 | `========------------ 42%` | 绿→黄→红 |
| ⑥ | 上下文占用 + 上限 | `ctx: 18.5K/3.2K /200.0K` | 亮白色 + 进度条颜色 |
| ⑦ | 单次调用 | `call: i5.0K o1.2K` | 亮白色 |
| ⑧ | Git | `git:main @github` | 青色 |
| ⑨ | 会话 / 累计耗时 | `time 5m / 19h39m` | 蓝色 |
| ⑩ | 会话 / subagent / 项目费用 | `¥0.004 / ¥0.001 / ¥0.009` | 绿→黄→红 |

### 工作原理

在精简版流程之外，slineplus 还会：

1. 读写 `statusline_state_<项目>.json` 中的累计数据（每个项目一个独立文件，区分会话费用和累计费用）。费用按模型存储：每条消息用其对应模型的 INI 定价实时计算并累加，而非事后用当前模型价格重算。
2. **定期扫描 `~/.claude/projects/<项目>/*.jsonl`** 获取 subagent API 调用的 token 用量，按 `model` 字段分组，每组用对应模型的 INI 价格计算费用并累加到项目总费用。同时通过会话启动时的基线快照隔离本次会话的 subagent 费用。
3. 从 `statusline.ini` 加载当前模型的定价（缺失则用默认值）
4. 当 `current_usage` 与上次相同时跳过累加（防止防抖重复计入）
5. 输出主会话费用 / subagent 费用 / 项目总费用，以及会话耗时 / 项目累计耗时

状态文件按项目目录独立追踪。新会话启动时会话费用清零，项目累计费用保留。累计耗时同样跨会话持续累加。

### 常见问题

#### 费用是怎么计算的？

费用由 **4 种 Token 的累计消耗 × 对应单价** 计算得出：

| Token 类型 | 数据来源 | INI 配置项 |
|-----------|---------|-----------|
| 输入 | `current_usage.input_tokens` | `input_price` |
| 输出 | `current_usage.output_tokens` | `output_price` |
| 缓存写入 | `current_usage.cache_creation_input_tokens` | `cache_write_price` |
| 缓存读取 | `current_usage.cache_read_input_tokens` | `cache_read_price` |

公式：`Σ(累计Token / 1,000,000 × 单价)`

单价从 `statusline.ini` 读取，按当前模型的 `[section]` 匹配，未匹配时回退到 `[default]`。

#### Token 是从项目开始累计的，还是只算当前会话？

**两者同时追踪，且按模型计费。** 费用显示格式为 `主会话费用 / subagent 费用 / 项目总费用`：

- **主会话费用**（左）：每次启动 Claude Code 新会话时清零，只统计本次对话的主会话消耗。每条消息使用该消息对应模型的 INI 定价实时计算并累加，切换模型不影响历史费用。
- **Subagent 费用**（中）：仅统计当前会话期间产生的 subagent 消耗（通过 JSONL 扫描差值计算，每条 JSONL 消息按 `model` 字段分组，使用对应模型定价算费）。
- **项目总费用**（右）：该项目的累计总费用，跨会话持续累加，包含主会话和 subagent。同样按模型计费，切换 API 提供商不会归零。

Token 按**项目目录**独立追踪 — 不同项目有各自的计数器，存储在各自的 `statusline_state_<项目>.json` 文件中。

#### 为什么 `claude -c` / `claude --continue` 不会重置会话费用？

`claude --continue`（别名 `-c`）会保留上次对话的 `session_id`。脚本检测到「相同的 session_id」后判定为同一次会话，继续累加而不是重置。

相反，`/resume`（应用内斜杠命令）会分配一个**新的** `session_id`，从而触发会话费用重置。

**如果你希望在加载上次对话的同时获得全新的会话费用统计**，使用：

```bash
claude --continue --fork-session
```

这会创建一个新的 `session_id` 但加载上次对话，脚本会将会话费用清零，同时保留项目累计费用。

#### 如何重置累计时间 / 累计费用？

如果想清空项目的累计时间（`time XhYm` 的右侧值）和累计费用，有两种方式：

1. **删除状态文件** — 最彻底，所有累计数据（token、费用、时长）全部清零：
   ```bash
   rm ~/.claude/statusline/statusline_state_<项目>.json
   ```
   下次发送消息后脚本会自动重新创建，从零开始。

2. **部分重置** — 只清零累计字段，保留当前会话数据：
   ```bash
   # 用 jq 将累计值设为当前会话值
   cat ~/.claude/statusline/statusline_state_<项目>.json | jq '
     .cumulative_input = .session_input |
     .cumulative_output = .session_output |
     .cumulative_duration_ms = .session_duration_ms
   ' > /tmp/reset.json && mv /tmp/reset.json ~/.claude/statusline/statusline_state_<项目>.json
   ```

> 项目名称 `<>` 中的部分对应工作目录路径脱敏后的形式（如 `/home/user/work/my-project` 对应 `_home_user_work_my-project`）。

#### 开启新会话时如何计算？

当 Claude Code 以一个**新的** `session_id`（与状态文件中存储的不同）启动会话时，脚本会：

1. 检测到 `session_id` 不匹配 → 判定为新会话
2. **重置会话计数器**为零（重新开始累加）
3. **保留累计计数器**（项目总计继续增长）
4. 显示 `主会话费用 / subagent 费用 / 项目总费用`（JSONL 扫描可用时）或 `会话费用/项目累计费用`（尚未扫描时）

这是 `claude`（全新启动）、`claude --continue --fork-session` 和 `/resume` 的正常行为 — 这三种方式都会分配新的 `session_id`。

> 如果手动删除或损坏了 `statusline_state_<项目>.json`，对应项目的累计记录会丢失，从零开始重新计算。

## License

MIT
