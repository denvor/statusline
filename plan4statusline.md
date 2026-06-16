# Statusline 增加 Subagent 统计 — 实施计划

## 背景

statusline 当前只统计**主会话**的 token 用量（从 Claude Code 运行时 API 获取），不包含 subagents 产生的消耗。
claude-monitor 虽然扫描 JSONL 文件包含 subagent，但它读取全部项目且不支持实时状态行显示。

**目标**：在 statusline 中增加 subagent 统计，状态行同时显示**主会话费用**和**含 subagent 的总费用**。

---

## 改动概览

| 文件 | 改动量 | 说明 |
|------|--------|------|
| `statusline.ps1` | ~80 行 | 核心：JSONL 扫描函数 + 周期性触发 + 新字段渲染 |
| `statusline.sh` | ~100 行 | 同上，bash 版本 |
| `statusline.ini` | 1-2 行 | `[display]` 加 `cost_sub` |
| `install.ps1` | 0 行 | 无需改动 |
| `install.sh` | 0 行 | 无需改动 |

---

## Step 1：状态文件新增字段

当前状态文件 `~/.claude/statusline/statusline_state_<project>.json` 新增：

```json
{
  "session_id": "...",
  "session_input": 0,
  "session_output": 0,
  "session_cache_write": 0,
  "session_cache_read": 0,
  "cumulative_input": 0,
  "cumulative_output": 0,
  "cumulative_cache_write": 0,
  "cumulative_cache_read": 0,
  "last_input": 0,
  "last_output": 0,
  "last_cache_write": 0,
  "last_cache_read": 0,

  "jsonl_input": 0,              // ← 新增
  "jsonl_output": 0,              // ← 新增
  "jsonl_cache_write": 0,         // ← 新增
  "jsonl_cache_read": 0            // ← 新增
}
```

**字段含义**：

| 字段族 | 来源 | 含 subagent |
|--------|------|-------------|
| `session_*` | 运行时 API（每次触发累加） | ❌ |
| `cumulative_*` | 跨会话累加 | ❌ |
| `jsonl_*` | 周期性扫描 JSONL 文件 | ✅ |

---

## Step 2：JSONL 扫描函数（PowerShell）

```powershell
$script:jsonlSyncCounter = 0
$script:jsonlCachedCost = $null
$script:jsonlCachedInput = 0
$script:jsonlCachedOutput = 0
$script:jsonlSyncInterval = 10   # 每 10 次触发同步一次

function Sync-JsonlCost {
    param([string]$ProjectDir)

    $projectsDir = Join-Path $env:USERPROFILE '.claude' 'projects'
    $sessionDirName = Split-Path $ProjectDir -Leaf
    $targetDir = Join-Path $projectsDir $sessionDirName
    if (-not (Test-Path $targetDir)) { return $null }

    $totalInput = 0; $totalOutput = 0; $totalCW = 0; $totalCR = 0
    $seen = @{}   # 去重签名哈希集

    Get-ChildItem $targetDir -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Get-Content $_.FullName -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
                $line = $_.Trim()
                if (-not $line) { return }
                try { $data = $line | ConvertFrom-Json } catch { return }

                if ($data.type -ne 'assistant') { return }
                $msg = $data.message
                if (-not $msg) { return }
                $usage = $msg.usage
                if (-not $usage) { return }

                $i = [int]($usage.input_tokens -or 0)
                $o = [int]($usage.output_tokens -or 0)
                if ($i -eq 0 -and $o -eq 0) { return }

                # 按 (timestamp, input, output) 签名去重
                $sig = "$($data.timestamp)|$i|$o"
                if ($seen.ContainsKey($sig)) { return }
                $seen[$sig] = $true

                $totalInput += $i
                $totalOutput += $o
                $totalCW += [int]($usage.cache_creation_input_tokens -or 0)
                $totalCR += [int]($usage.cache_read_input_tokens -or 0)
            }
        } catch { }
    }

    if ($totalInput -eq 0 -and $totalOutput -eq 0) { return $null }
    return @{ input = $totalInput; output = $totalOutput; cw = $totalCW; cr = $totalCR }
}
```

**去重说明**：JSONL 文件中存在重复记录（相同时间戳+用量但不同 UUID）。用 `"$timestamp|$input|$output"` 签名去重能避免双倍计数。

---

## Step 3：JSONL 扫描函数（bash）

```bash
# 全局变量
JSONL_SYNC_COUNTER=0
JSONL_CACHED_COST=""
JSONL_SYNC_INTERVAL=10

sync_jsonl_cost() {
    local project_dir="$1"
    local session_dir_name
    session_dir_name=$(basename "$project_dir")
    local target_dir="${HOME}/.claude/projects/${session_dir_name}"

    if [ ! -d "$target_dir" ]; then
        return 1
    fi

    # 用 jq 一次扫描所有 JSONL（含 subagents）
    # 1. 只取 type=assistant 且有 usage 的条目
    # 2. 按 (timestamp, input, output) 去重
    # 3. 累加 token 用量
    local result
    result=$(find "$target_dir" -name '*.jsonl' -type f 2>/dev/null | \
        xargs cat 2>/dev/null | \
        jq -s '
            [ .[] | select(.type == "assistant")
                  | .message.usage // empty
                  | select((.input_tokens // 0) + (.output_tokens // 0) > 0)
            ] as $all
            | $all
            | unique_by("\(.timestamp)|\(.input_tokens)|\(.output_tokens)")
            | { input: [.[].input_tokens] | add // 0,
                output: [.[].output_tokens] | add // 0,
                cw: [.[].cache_creation_input_tokens] | add // 0,
                cr: [.[].cache_read_input_tokens] | add // 0 }
        ' 2>/dev/null) || true

    if [ -z "$result" ] || [ "$result" = "null" ]; then
        return 1
    fi

    echo "$result"
}
```

`unique_by` 是 jq 1.6+ 的特性，注意兼容性。如果不支持可用 `reduce` 手动去重。

使用方式：

```bash
# 主逻辑中
JSONL_SYNC_COUNTER=$((JSONL_SYNC_COUNTER + 1))
if [ "$JSONL_SYNC_COUNTER" -ge "$JSONL_SYNC_INTERVAL" ]; then
    JSONL_SYNC_COUNTER=0
    jsonl_result=$(sync_jsonl_cost "$project_key" 2>/dev/null) || true
    if [ -n "$jsonl_result" ]; then
        jsonl_input=$(echo "$jsonl_result" | jq -r '.input')
        jsonl_output=$(echo "$jsonl_result" | jq -r '.output')
        jsonl_cw=$(echo "$jsonl_result" | jq -r '.cw')
        jsonl_cr=$(echo "$jsonl_result" | jq -r '.cr')
        jsonl_cost=$(calc_cost "$jsonl_input" "$jsonl_output" "$jsonl_cw" "$jsonl_cr")
        JSONL_CACHED_COST="$jsonl_cost"
    fi
fi
```

---

## Step 4：周期性触发机制

### PowerShell

在 `statusline.ps1` 主逻辑开头（去重逻辑之前）：

```powershell
# === 周期性 JSONL 同步 ===
$script:jsonlSyncCounter++
if ($script:jsonlSyncCounter -ge $script:jsonlSyncInterval) {
    $script:jsonlSyncCounter = 0
    $jsonlResult = Sync-JsonlCost -ProjectDir $projectKey
    if ($jsonlResult) {
        $script:jsonlCachedCost = Calc-Cost $jsonlResult.input $jsonlResult.output `
            $jsonlResult.cw $jsonlResult.cr
        $script:jsonlCachedInput = $jsonlResult.input
        $script:jsonlCachedOutput = $jsonlResult.output
    }
}
```

### bash

同理，在主逻辑的去重/累加部分之前：

```bash
# === 周期性 JSONL 同步 ===
JSONL_SYNC_COUNTER=$((JSONL_SYNC_COUNTER + 1))
if [ "$JSONL_SYNC_COUNTER" -ge "$JSONL_SYNC_INTERVAL" ]; then
    JSONL_SYNC_COUNTER=0
    jsonl_result=$(sync_jsonl_cost "$project_key" 2>/dev/null) || true
    if [ -n "$jsonl_result" ]; then
        JSONL_CACHED_COST=$(echo "$jsonl_result" | jq -r '(.input * input_price + .output * output_price + .cw * cache_write_price + .cr * cache_read_price) / 1000000')
    fi
fi
```

---

## Step 5：状态行显示

### 新增 `cost_sub` 显示字段

```powershell
# PowerShell
$jsonlCost = $script:jsonlCachedCost
if ($jsonlCost -and $jsonlCost -gt 0) {
    $jsonlCostColor = if ($jsonlCost -ge 1.0) { $bred } `
                 elseif ($jsonlCost -ge 0.5) { $byellow } `
                 else { $bgreen }
    $fields['cost_sub'] = "${dim}sub:${rst}${bold}${jsonlCostColor}" +
        "${currencySymbol}$($jsonlCost.ToString('F3'))${rst}"
} else {
    $fields['cost_sub'] = ''
}
```

```bash
# bash
if [ -n "$JSONL_CACHED_COST" ]; then
    jsonl_cost_color="$bgreen"
    if (( $(echo "$JSONL_CACHED_COST >= 1.0" | bc -l) )); then
        jsonl_cost_color="$bred"
    elif (( $(echo "$JSONL_CACHED_COST >= 0.5" | bc -l) )); then
        jsonl_cost_color="$byellow"
    fi
    fields['cost_sub']="${dim}sub:${rst}${bold}${jsonl_cost_color}${currency_symbol}$(printf '%.3f' "$JSONL_CACHED_COST")${rst}"
else
    fields['cost_sub']=""
fi
```

### 显示效果

```
[PR] mdtools2 | Flash | ████------------ 15% | ... | ¥0.500 | sub:¥0.760
                                                          ↑         ↑
                                                     主会话     含subagent总费用
```

`cost` 字段保持不变显示主会话费用。新增 `cost_sub` 字段显示含 subagent 的总费用。

---

## Step 6：修改 statusline.ini

在 `[display]` 的 `order` 中加入 `cost_sub`：

```ini
[display]
order = project, model, thinking, effort, bar, ctx, call, git, time, cost, cost_sub
```

用户可以自由调整位置，比如放到 `cost` 前面，或去掉 `cost_sub` 恢复旧版行为。

**顺序建议**：`cost_sub` 放在 `cost` 后面，这样主会话费用在前，subagent 总费用在后，一目了然。

---

## Step 7：异常处理

| 场景 | 表现 |
|------|------|
| JSONL 目录不存在 | `cost_sub` 不显示 |
| JSONL 扫描出错（格式异常等） | 静默忽略，`cost_sub` 使用上次缓存值 |
| 首次安装，从未扫描过 | `cost_sub` 不显示 |
| 项目没有 subagents | `cost_sub` 的值约等于 `sessionCost`（合理） |
| JSONL 文件极大（扫描耗时 > 500ms） | 第 1 次可能会卡，后续缓存命中无影响 |
| 扫描间隔内 token 无变化 | 正常，沿用上次缓存值 |

---

## Step 8：实施顺序

```
1. 修改 statusline.ps1
   ├── 添加全局变量（$script:jsonlSyncCounter 等）
   ├── 添加 Sync-JsonlCost 函数
   ├── 主逻辑添加周期性触发
   ├── 保存 jsonl_* 到状态文件
   └── 添加 cost_sub 字段渲染

2. 修改 statusline.sh（同步改动）
   ├── 添加全局变量
   ├── 添加 sync_jsonl_cost 函数
   ├── 主逻辑添加周期性触发
   └── 添加 cost_sub 字段渲染

3. 修改 statusline.ini
   └── display.order 加 cost_sub

4. 测试
   ├── 启动 Claude Code（任意项目）
   ├── 观察状态行首次出现 cost_sub（约 10 次触发后）
   ├── 使用含 subagents 的任务（如代码审查、多文件分析）
   └── 对比 claude-monitor 的结果
```

---

## 测试验证

```bash
# 1. 安装更新
cd D:\work\statusline
powershell -File install.ps1

# 2. 打开 Claude Code 开始工作
claude code

# 3. 状态行应该出现:
# [PR] mdtools2 | Flash | ... | ¥0.500 | sub:¥0.760

# 4. 用 claude-monitor 交叉验证
claude-monitor --view summary --data-path ~/.claude/projects/D--work-mdTools2

# 5. 回到 Claude Code 确认 sub 值与 claude-monitor 相近
```
