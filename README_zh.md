# Claude Code 状态栏美化脚本

[![en](https://img.shields.io/badge/lang-English-red.svg)](README.md)

基于 PowerShell / bash 的 [Claude Code](https://code.claude.com/docs/zh-CN/overview) 自定义状态栏，专为**第三方 API 用户**（如 DeepSeek）设计。在终端底部单行显示项目名、模型名、上下文用量、Token 消耗和**自定义定价的费用**。

## 效果预览

> **说明：** 输出使用 ANSI 颜色码，直接在终端渲染。下方展示的是**实际视觉效果**，非原始文本。

```
┌─ 状态栏（显示在 Claude Code 底部）─────────────────────────────────────────────────┐
│ [PR] hello │ DeepSeek V4 Pro T H │ ========------------ 42% │ ctx: 18.5K/3.2K     │
│ /200K │ call: i5K o1.2K @github │ time 5m │ ¥0.028                             │
└──────────────────────────────────────────────────────────────────────────────────┘
```

各区域颜色区分，一目了然：

| 区域 | 示例 | 颜色 |
|------|------|------|
| 项目名 | `[PR] hello` | 青色粗体 |
| 模型 + 思考/强度 | `DeepSeek V4 Pro` `T` `H` | 洋红 / 青 / 黄 |
| 上下文进度条 | `========------------` | 绿 → 黄 → 红（随用量变化） |
| 百分比 | `42%` | 与进度条同色，粗体 |
| 上下文占用 | `ctx: 18.5K/3.2K` | 亮白色 |
| 上下文上限 | `/200K` | 与进度条同色，粗体 |
| 单次调用 | `call: i5K o1.2K` | 亮白色 |
| Git 信息 | `git:main @github` | 青色 |
| 会话时长 | `time 5m` | 蓝色 |
| 累计费用 | `¥0.028` | 绿 → 黄 → 红（随金额变化） |

## 功能特性

- **项目名** — 自动从工作目录提取
- **模型显示** — 美化 DeepSeek、Claude 系列模型名称
- **上下文进度条** — 20 字符宽度，50%/75% 阈值切换绿/黄/红色
- **Token 详情** — 同时显示上下文窗口占用（`ctx:`）和最近一次调用用量（`call:`）
- **自定义定价** — 从 `statusline.ini` 读取，输入/输出/缓存写入/缓存读取分别定价
- **多币种** — 支持 `¥`（CNY）或 `$`（USD）
- **会话累计费用** — Token 跨调用累加，切换会话自动清零
- **防抖去重** — 检测并跳过 Claude Code 300ms 防抖导致的重复调用
- **Git 信息** — 分支名 + 远程仓库（如 `@github`）
- **Worktree 感知** — git worktree 中显示 `[WT]` 前缀
- **会话时长** — 显示本次会话已用时间（如 `time 5m`），数据来自 `cost.total_duration_ms`
- **零依赖** — 纯 PowerShell，不需要 `jq` 或 Node.js

## 环境要求

- **Windows**：PowerShell 5.1+
- **Mac / Linux**：bash 3.2+、[jq](https://jqlang.github.io/jq/)（`brew install jq` / `apt install jq`）
- [Claude Code](https://code.claude.com/docs/zh-CN/overview) v2.1.90+

## 快速开始

### 1. 放置文件

| 平台 | 需要复制的文件 |
|------|--------------|
| Windows | `statusline.ps1` + `statusline.ini` |
| Mac / Linux | `statusline.sh` + `statusline.ini` |

复制到 `~/.claude/` 或项目根目录。

Mac / Linux 上还需赋予执行权限：

```bash
chmod +x ~/.claude/statusline.sh
```

### 2. 配置 Claude Code

在 **已有的** `~/.claude/settings.json`（全局）或 `.claude/settings.json`（当前项目）中**添加** `"statusLine"` 键。注意是合并到现有配置中，**不要替换整个文件**：

**Windows：**
```jsonc
"statusLine": {
  "type": "command",
  "command": "powershell.exe -NoProfile -File \"C:/Users/你的用户名/.claude/statusline.ps1\"",
  "padding": 0
}
```

**Mac / Linux：**
```jsonc
"statusLine": {
  "type": "command",
  "command": "$HOME/.claude/statusline.sh",
  "padding": 0
}
```

Windows 用户请将 `你的用户名` 替换为实际用户名。

### 3. 设置定价

编辑 `statusline.ini`：

```ini
# 默认定价 — 未匹配到具体模型时使用
[default]
input_price=3.00
output_price=6.00
cache_write_price=3.00
cache_read_price=0.025
currency=CNY

# 模型专属定价 — 按 Claude Code 传入的模型 ID 精确匹配
[deepseek-v4-pro]
input_price=3.00
output_price=6.00
cache_write_price=3.00
cache_read_price=0.025
currency=CNY
```

- `currency=CNY` → 显示 `¥`
- `currency=USD` → 显示 `$`
- 定价按 `[模型ID]` 分段，脚本根据当前使用的模型自动匹配
- 未匹配到时回退到 `[default]` 段

### 4. 在 Claude Code 中发送任意消息

状态栏会在首次交互后显示在终端底部。

## 配置说明

### `statusline.ini` 参数

定价通过 `[模型ID]` 分段配置，脚本根据当前模型自动匹配。段名必须与 Claude Code 传入的 `model.display_name` 原始值完全一致（如 `deepseek-v4-pro`）。

| 键 | 说明 | 默认值 |
|----|------|--------|
| `[default]` | 未匹配到具体模型时的回退定价 | — |
| `input_price` | 每百万输入 Token 价格 | `3.00` |
| `output_price` | 每百万输出 Token 价格 | `6.00` |
| `cache_write_price` | 每百万缓存写入 Token 价格 | `3.00` |
| `cache_read_price` | 每百万缓存读取 Token 价格 | `0.025` |
| `currency` | 货币：`CNY` 或 `USD` | `CNY` |

每个 `[模型ID]` 段内可独立配置以上 5 个 key。如果 INI 文件缺失，使用硬编码默认值。

### Token 类型说明

| 类型 | 计费时机 |
|------|----------|
| 输入（Input） | 每次发送给模型的提示词 |
| 输出（Output） | 模型生成的每个 Token |
| 缓存写入（Cache write） | 写入 Claude 提示缓存的 Token |
| 缓存读取（Cache read） | 命中缓存的 Token（通常为输入价格的 1-25%） |

## 输出布局

```
[图标] 项目名 │ 模型 模式 │ ========------ 42% │ ctx: 18.5K/3.2K /200K │ call: i5K o1.2K git:main @github │ time 5m │ ¥0.028
  ①      ②      ③   ④             ⑤                         ⑥               ⑦                   ⑧            ⑨
```

| # | 字段 | 渲染效果 | 颜色 |
|---|------|---------|------|
| ① | 项目 | `[PR] hello` | 青色粗体 |
| ② | 模型 + 模式 | `DeepSeek V4 Pro` `T` `H` | 洋红 / 青 / 黄 |
| ③ | 进度条 + 百分比 | `========------------ 42%` | 绿→黄→红 |
| ④ | 上下文占用 | `ctx: 18.5K/3.2K` | 亮白色 |
| ⑤ | 上下文上限 | `/200K` | 与进度条同色，粗体 |
| ⑥ | 单次调用 | `call: i5K o1.2K` | 亮白色 |
| ⑦ | Git | `git:main @github` | 青色 |
| ⑧ | 会话时长 | `time 5m` | 蓝色 |
| ⑨ | 累计费用 | `¥0.028` | 绿→黄→红 |

> **图标说明：** `T` = 扩展思考已开启，`H`/`X`/`M`/`L` = 推理强度（高/极高/中/低），`[WT]` = 处于 git worktree 中

## 工作原理

Claude Code 在每次助手消息后通过 stdin 向脚本传入 JSON 快照。脚本执行流程：

1. 解析 JSON（`ConvertFrom-Json`）
2. 从 `context_window.current_usage` 提取单次调用的 Token 数
3. 读写 `statusline_state.json` 中的累计数据（按 `session_id` 区分会话）
4. 从 `statusline.ini` 加载定价（缺失则用默认值）
5. 计算费用：`Σ(累计Token / 1,000,000 × 单价)`，覆盖四种 Token 类型
6. 当 `current_usage` 与上次相同时跳过累加（防止防抖重复计入）
7. 输出一行 ANSI 彩色文本到 stdout

会话 ID 变化时，累计数据自动清零。

## 文件说明

| 文件 | 用途 |
|------|------|
| `statusline.ps1` | Windows 脚本 — 读取 stdin，累计 Token，输出状态栏 |
| `statusline.sh` | Mac / Linux 脚本 — 功能相同，使用 jq 解析 JSON |
| `statusline.ini` | 用户可编辑的定价配置 |
| `statusline_state.json` | 自动生成 — 持久化每个会话的累计 Token 数 |

## 常见问题

### 费用是怎么计算的？

费用由 **4 种 Token 的累计消耗 × 对应单价** 计算得出：

| Token 类型 | 数据来源 | INI 配置项 |
|-----------|---------|-----------|
| 输入 | `current_usage.input_tokens` | `input_price` |
| 输出 | `current_usage.output_tokens` | `output_price` |
| 缓存写入 | `current_usage.cache_creation_input_tokens` | `cache_write_price` |
| 缓存读取 | `current_usage.cache_read_input_tokens` | `cache_read_price` |

公式：`Σ(累计Token / 1,000,000 × 单价)`

单价从 `statusline.ini` 读取，按当前模型的 `[section]` 匹配，未匹配时回退到 `[default]`。

### Token 是从项目开始累计的，还是只算当前会话？

**按会话累计。** Claude Code 每次启动会生成一个新的 `session_id`。脚本将累计数据持久化到 `statusline_state.json`，按 `session_id` 区分：

- **同一会话内**：Token 持续累加（有去重机制防止重复计算）
- **新会话**（关闭重开 Claude Code）：检测到 `session_id` 变化 → 自动清零，重新开始

### Resume 恢复会话时会怎么计算？

Resume 恢复的是**同一个** `session_id`，脚本会继续累加，不会清零。

1. Claude Code 恢复会话时传入相同的 `session_id`
2. 脚本比对 `statusline_state.json` 中存储的 `session_id` → 匹配，判定为同一会话
3. 从 state 文件加载之前的累计 Token 数，在此基础上继续累加
4. 费用 = 之前累计的费用 + 新产生的费用

关闭重开再 resume，费用是连续累计的；只有全新会话才会重置。

> 如果手动删除或损坏了 `statusline_state.json`，之前的累计记录会丢失，从零开始重新计算。

## License

MIT
