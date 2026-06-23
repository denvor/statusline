# statusline — Simplified stdin-only statusline (PowerShell)
# Displays: project name | model | context usage bar | session time
param()

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Read JSON from stdin
$rawJson = ''
try {
    $reader = [System.IO.StreamReader]::new([Console]::OpenStandardInput())
    $rawJson = $reader.ReadToEnd()
    $reader.Close()
} catch {
    Write-Output "Claude Code"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($rawJson)) {
    Write-Output "Claude Code"
    exit 0
}

# 2. Parse JSON
try {
    $data = $rawJson | ConvertFrom-Json
} catch {
    Write-Output "Claude Code"
    exit 0
}

# 3. Extract fields
$projectName = ''
if ($data.workspace.project_dir) {
    $projectName = Split-Path $data.workspace.project_dir -Leaf
} elseif ($data.cwd) {
    $projectName = Split-Path $data.cwd -Leaf
}
if ([string]::IsNullOrWhiteSpace($projectName) -and $data.workspace.repo.name) {
    $projectName = $data.workspace.repo.name
}
if ([string]::IsNullOrWhiteSpace($projectName)) { $projectName = '...' }

# Model name
$modelRaw = if ($data.model.display_name) { $data.model.display_name } else { 'Unknown' }
# Strip [1m] / [1M] context suffix
$modelClean = $modelRaw -replace '\s*\[1[mM]\]$', ''
$modelDisplay = switch -Regex ($modelClean) {
    '^deepseek-v4-pro$'   { 'DeepSeek V4 Pro'; break }
    '^deepseek-v4-flash$' { 'DeepSeek V4 Flash'; break }
    'deepseek.*pro'       { 'DeepSeek Pro'; break }
    'deepseek.*flash'     { 'DeepSeek Flash'; break }
    '^claude-opus-4-8$'   { 'Opus 4.8'; break }
    '^claude-opus-4-7$'   { 'Opus 4.7'; break }
    'claude-opus'         { 'Opus'; break }
    '^claude-sonnet-4-6$' { 'Sonnet 4.6'; break }
    '^claude-sonnet-4-5$' { 'Sonnet 4.5'; break }
    'claude-sonnet'       { 'Sonnet'; break }
    'claude-haiku'        { 'Haiku'; break }
    default               { $modelClean }
}

# Context usage
$contextPct = 0
if ($null -ne $data.context_window.used_percentage) {
    $contextPct = [math]::Floor([double]$data.context_window.used_percentage)
}
$contextSize = 200000
if ($data.context_window.context_window_size) {
    $contextSize = [int]$data.context_window.context_window_size
}

# Context tokens (for ctx display)
$inputTokens  = if ($data.context_window.total_input_tokens)  { [int]$data.context_window.total_input_tokens }  else { 0 }
$outputTokens = if ($data.context_window.total_output_tokens) { [int]$data.context_window.total_output_tokens } else { 0 }

# Current message tokens (for call: display)
$curIn  = if ($data.context_window.current_usage.input_tokens)  { [int]$data.context_window.current_usage.input_tokens }  else { 0 }
$curOut = if ($data.context_window.current_usage.output_tokens) { [int]$data.context_window.current_usage.output_tokens } else { 0 }

# Session time
$durationMs = if ($data.cost.total_duration_ms) { [int64]$data.cost.total_duration_ms } else { 0 }

# Git branch
$gitBranch = ''
$projectDir = if ($data.workspace.project_dir) { $data.workspace.project_dir } else { $data.cwd }
if ($projectDir) {
    try {
        Push-Location $projectDir
        $branch = git branch --show-current 2>$null
        if ($branch) { $gitBranch = $branch.Trim() }
    } catch {}
    finally { Pop-Location }
}

# Effort & thinking
$effortLevel   = if ($data.effort.level)   { $data.effort.level }   else { '' }
$thinkingEnabled = if ($data.thinking.enabled) { $data.thinking.enabled } else { $false }

# Worktree
$isWorktree = $false
if (($data.worktree.name) -or ($data.workspace.git_worktree)) { $isWorktree = $true }

# 4. Read INI display config
$scriptDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { "$env:HOMEDRIVE$env:HOMEPATH" }
$statuslineDir = Join-Path $scriptDir '.claude/statusline'
$iniPath = Join-Path $statuslineDir 'statusline.ini'

$orderFromIni = $null
if (Test-Path $iniPath) {
    try {
        foreach ($line in (Get-Content $iniPath -Encoding UTF8 -ErrorAction Stop)) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\[display\]$') { $currentSection = 'display'; continue }
            if ($currentSection -eq 'display' -and $trimmed -match '^order\s*=\s*(.+)$') {
                $orderFromIni = $Matches[1]; break }
        }
    } catch {}
}
# 5. Duration formatting
function Format-Duration($ms) {
    if (-not $ms -or $ms -eq 0) { return '' }
    $totalSec = [int]($ms / 1000)
    if ($totalSec -lt 60) { return "${totalSec}s" }
    $min = [int]($totalSec / 60)
    if ($min -lt 60) { return "${min}m" }
    $hr  = [int]($min / 60)
    $rem = $min % 60
    return "${hr}h${rem}m"
}
$durationStr = Format-Duration $durationMs

# 6. Number formatting
function Format-Num($n) {
    if ($n -ge 1000000) {
        $t = [int](($n * 10 + 500000) / 1000000)
        return "$([int]($t/10)).$($t%10)M"
    } elseif ($n -ge 1000) {
        $t = [int](($n * 10 + 500) / 1000)
        return "$([int]($t/10)).$($t%10)K"
    } else { return $n.ToString() }
}

$inputStr  = Format-Num $inputTokens
$outputStr = Format-Num $outputTokens
$callInStr = Format-Num $curIn
$callOutStr = Format-Num $curOut
$contextSizeStr = Format-Num $contextSize

# 7. Icons
$effortIcon = switch ($effortLevel) {
    'xhigh' { 'X' }; 'high' { 'H' }; 'medium' { 'M' }; 'low' { 'L' }; 'max' { '!' }
    default { '' }
}
$thinkingIcon = if ($thinkingEnabled) { 'T' } else { '' }
$projectIcon  = if ($isWorktree) { 'WT' } else { 'PR' }

# 8. ANSI colors
$e = [char]27
$rst   = "${e}[0m"
$bold  = "${e}[1m"
$dim   = "${e}[2m"
$cyan  = "${e}[36m"
$green = "${e}[32m"
$magenta   = "${e}[35m"
$bcyan     = "${e}[96m"
$bgreen    = "${e}[92m"
$byellow   = "${e}[93m"
$bred      = "${e}[91m"
$bblue     = "${e}[94m"
$bmagenta  = "${e}[95m"
$bwhite    = "${e}[97m"

# 9. Progress bar (20 chars)
$barWidth = 20
$filled = [math]::Min([math]::Max([int]($contextPct * $barWidth / 100), 0), $barWidth)
if ($contextPct -gt 0 -and $filled -eq 0) { $filled = 1 }
$empty = $barWidth - $filled

if ($contextPct -gt 75) { $barColor = $bred }
elseif ($contextPct -gt 50) { $barColor = $byellow }
else { $barColor = $bgreen }

$barFilled = if ($filled -gt 0) { ('=' * $filled) } else { '' }
$barEmpty  = if ($empty -gt 0)  { ('-' * $empty) } else { '' }
$bar = "${barColor}${barFilled}${dim}${barEmpty}${rst}"
$pctStr = $contextPct.ToString().PadLeft(3)


# 10. Display order
$displayOrder = @('project', 'model', 'thinking', 'effort', 'bar', 'ctx', 'call', 'git', 'time')
if ($orderFromIni) {
    $displayOrder = $orderFromIni.Split(',') | ForEach-Object { $_.Trim() }
}

# Build field map
$fields = @{}
$fields['project'] = "${bold}${bcyan}[${projectIcon}] ${projectName}${rst}"
$fields['model']   = "${bmagenta}${modelDisplay}${rst}"
$fields['thinking'] = if ($thinkingIcon) { "${bcyan}${thinkingIcon}${rst}" } else { '' }
$fields['effort']  = if ($effortIcon)   { "${byellow}${effortIcon}${rst}" } else { '' }
$fields['bar']     = "${bar} ${bold}${barColor}${pctStr}%${rst}"
$fields['ctx']     = "ctx: ${bwhite}${inputStr}/${outputStr}${rst} ${dim}/${bold}${barColor}${contextSizeStr}${rst}"
$fields['call']    = "call: ${bwhite}i${rst}${bwhite}${callInStr}${rst} ${bwhite}o${rst}${bwhite}${callOutStr}${rst}"

$gitField = ''
if ($gitBranch) {
    $gitField = "${cyan}git:${gitBranch}${rst}"
}
$fields['git'] = $gitField

$fields['time'] = if ($durationStr) { "${bblue}time ${rst}${durationStr}" } else { '' }

# Build line
$parts = @()
$sep = " ${dim}|${rst} "
foreach ($key in $displayOrder) {
    $val = $fields[$key]
    if ($val) { $parts += $val }
}
$line = $parts -join $sep

Write-Output $line
