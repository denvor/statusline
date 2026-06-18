# Claude Code Status Line (PowerShell)
# Displays: project name | model name | context usage bar | cost
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

# Model name - beautify common model IDs
$modelRaw = if ($data.model.display_name) { $data.model.display_name } else { 'Unknown' }
# Strip [1m] / [1M] context suffix added by third-party API providers
$modelClean = $modelRaw -replace '\s*\[1[mi]\]$', ''
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
$inputTokens  = if ($data.context_window.total_input_tokens)  { [int]$data.context_window.total_input_tokens }  else { 0 }
$outputTokens = if ($data.context_window.total_output_tokens) { [int]$data.context_window.total_output_tokens } else { 0 }

# =====================================================================
# Custom pricing from statusline.ini + token accumulation
# =====================================================================

$scriptDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { "$env:HOMEDRIVE$env:HOMEPATH" }
$statuslineDir = Join-Path $scriptDir '.claude/statusline'
$iniPath   = Join-Path $statuslineDir 'statusline.ini'

# Default pricing (DeepSeek V4, CNY) — used if INI is missing or invalid
$pricing = @{
    input_price       = 2.00
    output_price      = 8.00
    cache_write_price = 2.00
    cache_read_price  = 0.50
    currency          = 'CNY'
}

# Try to read INI file (section-based: [model_name] -> pricing, [display] -> order)
$iniSections = @{}
$orderFromIni = $null
$jsonlSyncInterval = 10   # 默认每 N 次触发扫描一次 JSONL（subagent 统计）
if (Test-Path $iniPath) {
    try {
        $currentSection = ''
        foreach ($line in (Get-Content $iniPath -Encoding UTF8 -ErrorAction Stop)) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^[#;]' -or $trimmed -eq '') { continue }
            if ($trimmed -match '^\[(.+)\]$') {
                $currentSection = $Matches[1].Trim()
                if (-not $iniSections.ContainsKey($currentSection)) {
                    $iniSections[$currentSection] = @{}
                }
                continue
            }
            if ($currentSection -and $trimmed -match '^\s*([^=]+?)\s*=\s*(.+?)\s*$') {
                $key = $Matches[1].Trim()
                $val = $Matches[2].Trim()
                if ($key -in @('input_price','output_price','cache_write_price','cache_read_price')) {
                    $iniSections[$currentSection][$key] = [double]$val
                } elseif ($key -eq 'currency') {
                    $iniSections[$currentSection]['currency'] = $val.ToUpper()
                } elseif ($currentSection -eq 'display' -and $key -eq 'order') {
                    $orderFromIni = $val
                } elseif ($currentSection -eq 'jsonl' -and $key -eq 'sync_interval') {
                    $jsonlSyncInterval = [int]$val
                }
            }
        }
    } catch {}
}

# Match pricing to current model, fallback to [default]
$matchedSection = if ($iniSections.ContainsKey($modelClean)) { $modelClean } else { 'default' }
if ($iniSections.ContainsKey($matchedSection)) {
    $section = $iniSections[$matchedSection]
    if ($section.ContainsKey('input_price'))       { $pricing['input_price']       = $section['input_price'] }
    if ($section.ContainsKey('output_price'))      { $pricing['output_price']      = $section['output_price'] }
    if ($section.ContainsKey('cache_write_price')) { $pricing['cache_write_price'] = $section['cache_write_price'] }
    if ($section.ContainsKey('cache_read_price'))  { $pricing['cache_read_price']  = $section['cache_read_price'] }
    if ($section.ContainsKey('currency'))          { $pricing['currency']          = $section['currency'] }
}

# Currency symbol
$currencySymbol = if ($pricing['currency'] -eq 'CNY') { [char]0xA5 } else { '$' }

# --- Token accumulation with dedup ---
$curIn  = if ($data.context_window.current_usage.input_tokens)              { [int]$data.context_window.current_usage.input_tokens }              else { 0 }
$curOut = if ($data.context_window.current_usage.output_tokens)             { [int]$data.context_window.current_usage.output_tokens }             else { 0 }
$curCW  = if ($data.context_window.current_usage.cache_creation_input_tokens) { [int]$data.context_window.current_usage.cache_creation_input_tokens } else { 0 }
$curCR  = if ($data.context_window.current_usage.cache_read_input_tokens)      { [int]$data.context_window.current_usage.cache_read_input_tokens }      else { 0 }
$sessionId = if ($data.session_id) { $data.session_id } else { 'unknown' }
$durationMs = if ($data.cost.total_duration_ms) { [int64]$data.cost.total_duration_ms } else { 0 }

# Project key for per-project tracking
$projectKey = if ($data.workspace.project_dir) { $data.workspace.project_dir } else { $data.cwd }
if (-not $projectKey) { $projectKey = 'unknown' }
$stateFile = 'statusline_state_' + ($projectKey -replace '[:\\/]', '_') + '.json'
$statePath = Join-Path $statuslineDir $stateFile

$cumIn = 0; $cumOut = 0; $cumCW = 0; $cumCR = 0
$sesIn = 0; $sesOut = 0; $sesCW = 0; $sesCR = 0
$projState = $null
if (Test-Path $statePath) {
    try {
        $rawState = [System.IO.File]::ReadAllText($statePath, [System.Text.UTF8Encoding]::new($false))
        $projState = $rawState | ConvertFrom-Json
    } catch {}
}

# Load cached JSONL scan results from state (persist across invocations)
$jsonlInput  = if ($projState.jsonl_input)  { [int]$projState.jsonl_input }  else { 0 }
$jsonlOutput = if ($projState.jsonl_output) { [int]$projState.jsonl_output } else { 0 }
$jsonlCW     = if ($projState.jsonl_cache_write) { [int]$projState.jsonl_cache_write } else { 0 }
$jsonlCR     = if ($projState.jsonl_cache_read)  { [int]$projState.jsonl_cache_read }  else { 0 }
$jsonlScanCount = if ($projState.jsonl_scan_count) { [int]$projState.jsonl_scan_count } else { 0 }
$jsonlBaselineInput  = if ($projState.jsonl_baseline_input)  { [int]$projState.jsonl_baseline_input }  else { 0 }
$jsonlBaselineOutput = if ($projState.jsonl_baseline_output) { [int]$projState.jsonl_baseline_output } else { 0 }
$jsonlBaselineCW     = if ($projState.jsonl_baseline_cache_write) { [int]$projState.jsonl_baseline_cache_write } else { 0 }
$jsonlBaselineCR     = if ($projState.jsonl_baseline_cache_read)  { [int]$projState.jsonl_baseline_cache_read }  else { 0 }
$jsonlEverScanned    = if ($projState.jsonl_ever_scanned) { $true } else { $false }

$sesDur = if ($projState.session_duration_ms) { [int64]$projState.session_duration_ms } else { 0 }
$sesDurBaseline = if ($projState.session_duration_baseline) { [int64]$projState.session_duration_baseline } else { 0 }
$cumDur = if ($projState.cumulative_duration_ms) { [int64]$projState.cumulative_duration_ms } else { 0 }

$isNewProject = (-not $projState)

# Check if session changed or new (per-project)
# Guard: if incoming session_id is "unknown" (compact), trust stored session_id
$isNewSession = $isNewProject -or (($sessionId -ne 'unknown') -and ($projState.session_id -ne $sessionId))

if ($isNewProject) {
    # Brand new project — start from scratch
    $cumIn = $curIn; $cumOut = $curOut; $cumCW = $curCW; $cumCR = $curCR
    $sesIn = $curIn; $sesOut = $curOut; $sesCW = $curCW; $sesCR = $curCR
    $sesDurBaseline = $durationMs; $cumDur = $durationMs
} elseif ($isNewSession) {
    # Same project, new session: session reset, cumulative preserved
    $cumIn  = [int]$projState.cumulative_input  + $curIn
    $cumOut = [int]$projState.cumulative_output + $curOut
    $cumCW  = [int]$projState.cumulative_cache_write + $curCW
    $cumCR  = [int]$projState.cumulative_cache_read  + $curCR
    $sesIn = $curIn; $sesOut = $curOut; $sesCW = $curCW; $sesCR = $curCR
    # New session: snapshot duration_ms as baseline, ses_dur starts from 0
    $sesDurBaseline = $durationMs
    $cumDur += $durationMs
} else {
    # Same session — check for duplicate (debounce)
    $lastIn  = if ($projState.last_input)  { [int]$projState.last_input }  else { 0 }
    $lastOut = if ($projState.last_output) { [int]$projState.last_output } else { 0 }
    $lastCW  = if ($projState.last_cache_write) { [int]$projState.last_cache_write } else { 0 }
    $lastCR  = if ($projState.last_cache_read)  { [int]$projState.last_cache_read }  else { 0 }

    $isDuplicate = ($curIn -eq $lastIn) -and ($curOut -eq $lastOut) -and
                   ($curCW -eq $lastCW) -and ($curCR -eq $lastCR)

    $cumIn  = if ($projState.cumulative_input)  { [int]$projState.cumulative_input }  else { 0 }
    $cumOut = if ($projState.cumulative_output) { [int]$projState.cumulative_output } else { 0 }
    $cumCW  = if ($projState.cumulative_cache_write) { [int]$projState.cumulative_cache_write } else { 0 }
    $cumCR  = if ($projState.cumulative_cache_read)  { [int]$projState.cumulative_cache_read }  else { 0 }
    $sesIn  = if ($projState.session_input)  { [int]$projState.session_input }  else { 0 }
    $sesOut = if ($projState.session_output) { [int]$projState.session_output } else { 0 }
    $sesCW  = if ($projState.session_cache_write) { [int]$projState.session_cache_write } else { 0 }
    $sesCR  = if ($projState.session_cache_read)  { [int]$projState.session_cache_read }  else { 0 }
    $sesDur = if ($projState.session_duration_ms) { [int64]$projState.session_duration_ms } else { 0 }
    $cumDur = if ($projState.cumulative_duration_ms) { [int64]$projState.cumulative_duration_ms } else { 0 }

    if (-not $isDuplicate -and ($curIn + $curOut + $curCW + $curCR) -gt 0) {
        $cumIn  += $curIn;  $cumOut += $curOut;  $cumCW  += $curCW;  $cumCR  += $curCR
        $sesIn  += $curIn;  $sesOut += $curOut;  $sesCW  += $curCW;  $sesCR  += $curCR
        # durationMs is session-cumulative: add only the delta since last recording
        $oldRawDur = $sesDurBaseline + $sesDur
        $durDelta = $durationMs - $oldRawDur
        if ($durDelta -lt 0) {
            $durDelta = $durationMs
        } elseif ($durDelta -gt 300000) {
            # Gap > 5 min: likely session restart, reset baseline and skip gap
            $sesDurBaseline = $durationMs
            $durDelta = 0
        }
        $cumDur += $durDelta
    }
}

# ses_dur = duration_ms - baseline (0 at session start, grows during session)
$sesDur = $durationMs - $sesDurBaseline
if ($sesDur -lt 0) {
    $sesDur = 0
} elseif ($sesDurBaseline -eq 0 -and $sesDur -gt 0 -and -not $isNewProject) {
    # Migration: old state file had no baseline field (null → 0).
    # sesDur loaded from state was the raw duration_ms from before the fix.
    # Reset baseline to current duration_ms so sesDur starts fresh.
    $sesDurBaseline = $durationMs
    $sesDur = 0
}

# New session: snapshot JSONL total as baseline for per-session subagent tracking
if ($isNewSession -and -not $isNewProject) {
    $jsonlBaselineInput  = $jsonlInput
    $jsonlBaselineOutput = $jsonlOutput
    $jsonlBaselineCW     = $jsonlCW
    $jsonlBaselineCR     = $jsonlCR
}

# --- Periodic JSONL scan for subagent cost ---
$jsonlScanCount++
if ($jsonlSyncInterval -gt 0 -and $jsonlScanCount -ge $jsonlSyncInterval) {
    $jsonlScanCount = 0
    try {
        $projectsDir = Join-Path (Join-Path $scriptDir '.claude') 'projects'
        $sessionDirName = $projectKey -replace '[:\\/]', '-'
        $targetDir = Join-Path $projectsDir $sessionDirName
        if (Test-Path $targetDir) {
            $jsonlTotalInput = 0; $jsonlTotalOutput = 0; $jsonlTotalCW = 0; $jsonlTotalCR = 0
            $jsseen = @{}
            Get-ChildItem $targetDir -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Get-Content $_.FullName -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
                        $line = $_.Trim()
                        if (-not $line) { return }
                        try { $jsdata = $line | ConvertFrom-Json } catch { return }
                        if ($jsdata.type -ne 'assistant') { return }
                        $jsmsg = $jsdata.message
                        if (-not $jsmsg) { return }
                        $jsusage = $jsmsg.usage
                        if (-not $jsusage) { return }
                        $ji = if ($null -ne $jsusage.input_tokens) { [int]$jsusage.input_tokens } else { 0 }
                        $jo = if ($null -ne $jsusage.output_tokens) { [int]$jsusage.output_tokens } else { 0 }
                        $jcw_local = if ($null -ne $jsusage.cache_creation_input_tokens) { [int]$jsusage.cache_creation_input_tokens } else { 0 }
                        $jcr_local = if ($null -ne $jsusage.cache_read_input_tokens) { [int]$jsusage.cache_read_input_tokens } else { 0 }
                        if ($ji -eq 0 -and $jo -eq 0 -and $jcw_local -eq 0 -and $jcr_local -eq 0) { return }
                        $jssig = "$($jsdata.timestamp)|$ji|$jo"
                        if ($jsseen.ContainsKey($jssig)) { return }
                        $jsseen[$jssig] = $true
                        $jsonlTotalInput += $ji; $jsonlTotalOutput += $jo
                        $jsonlTotalCW += $jcw_local; $jsonlTotalCR += $jcr_local
                    }
                } catch { }
            }
            if ($jsonlTotalInput -gt 0 -or $jsonlTotalOutput -gt 0 -or $jsonlTotalCW -gt 0 -or $jsonlTotalCR -gt 0) {
                $jsonlInput = $jsonlTotalInput; $jsonlOutput = $jsonlTotalOutput
                $jsonlCW = $jsonlTotalCW; $jsonlCR = $jsonlTotalCR
            }
        }
        $jsonlEverScanned = $true
    } catch { }
}

# Save state (single project per file)
try {
    # Ensure statusline directory exists
    New-Item -ItemType Directory -Path $statuslineDir -Force | Out-Null
    $newState = @{
        session_id             = $sessionId
        session_input          = $sesIn
        session_output         = $sesOut
        session_cache_write    = $sesCW
        session_cache_read     = $sesCR
        cumulative_input       = $cumIn
        cumulative_output      = $cumOut
        cumulative_cache_write = $cumCW
        cumulative_cache_read  = $cumCR
        last_input             = $curIn
        last_output            = $curOut
        last_cache_write       = $curCW
        last_cache_read        = $curCR
        jsonl_input            = $jsonlInput
        jsonl_output           = $jsonlOutput
        jsonl_cache_write      = $jsonlCW
        jsonl_cache_read       = $jsonlCR
        jsonl_scan_count       = $jsonlScanCount
        jsonl_ever_scanned     = $jsonlEverScanned
        jsonl_baseline_input   = $jsonlBaselineInput
        jsonl_baseline_output  = $jsonlBaselineOutput
        jsonl_baseline_cache_write = $jsonlBaselineCW
        jsonl_baseline_cache_read  = $jsonlBaselineCR
        session_duration_ms        = $sesDur
        session_duration_baseline  = $sesDurBaseline
        cumulative_duration_ms     = $cumDur
    } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($statePath, $newState, [System.Text.UTF8Encoding]::new($false))
} catch {}

# --- Calculate cost from custom pricing ---
function Calc-Cost($i, $o, $cw, $cr) {
    $v = ($i / 1000000.0) * $pricing['input_price'] +
         ($o / 1000000.0) * $pricing['output_price'] +
         ($cw / 1000000.0) * $pricing['cache_write_price'] +
         ($cr / 1000000.0) * $pricing['cache_read_price']
    return $v
}
$sessionCost    = Calc-Cost $sesIn $sesOut $sesCW $sesCR
$cumulativeCost = Calc-Cost $cumIn $cumOut $cumCW $cumCR

# Fallback to Claude Code's built-in cost if both are 0
if ($cumulativeCost -eq 0.0 -and $data.cost.total_cost_usd) {
    $cumulativeCost = [double]$data.cost.total_cost_usd
}

# Session duration
function Format-Duration($ms) {
    if ($null -eq $ms -or $ms -eq 0) { return '' }
    $totalSec = [math]::Floor([int64]$ms / 1000)
    if ($totalSec -lt 60) { return "${totalSec}s" }
    $min = [math]::Floor($totalSec / 60)
    if ($min -lt 60) { return "${min}m" }
    $hr = [math]::Floor($min / 60)
    return "${hr}h$($min % 60)m"
}
$sesDurStr = Format-Duration $sesDur
$cumDurStr = Format-Duration $cumDur
$durationStr = if ($sesDurStr -and $cumDurStr) { "${sesDurStr} / ${cumDurStr}" } elseif ($sesDurStr) { $sesDurStr } else { '' }

# Worktree?
$isWorktree = ($data.worktree.name -or $data.workspace.git_worktree)

# Git branch
$gitBranch = ''
$repoHost  = ''
if ($data.workspace.repo.host) {
    $repoHost = $data.workspace.repo.host -replace '\.com$', '' -replace '\.org$', ''
}
try {
    $projectDir = if ($data.workspace.project_dir) { $data.workspace.project_dir } else { $data.cwd }
    if ($projectDir) {
        $branch = git -C $projectDir branch --show-current 2>$null
        if ($branch) { $gitBranch = $branch.Trim() }
    }
} catch {}

# Effort level icon
$effortIcon = ''
if ($data.effort.level) {
    switch ($data.effort.level) {
        'xhigh' { $effortIcon = 'X' }
        'high'  { $effortIcon = 'H' }
        'medium'{ $effortIcon = 'M' }
        'low'   { $effortIcon = 'L' }
        'max'   { $effortIcon = '!' }
    }
}

# Thinking mode
$thinkingIcon = ''
if ($data.thinking.enabled) { $thinkingIcon = 'T' }

# 4. ANSI colors
$e      = [char]27
$rst    = "${e}[0m"
$bold   = "${e}[1m"
$dim    = "${e}[2m"
$cyan   = "${e}[36m"
$green  = "${e}[32m"
$yellow = "${e}[33m"
$red    = "${e}[31m"
$blue   = "${e}[34m"
$magenta= "${e}[35m"
$bcyan  = "${e}[96m"
$bgreen = "${e}[92m"
$byellow= "${e}[93m"
$bred   = "${e}[91m"
$bblue  = "${e}[94m"
$bmagenta = "${e}[95m"
$bwhite = "${e}[97m"

# 5. Progress bar (20 chars)
$barWidth = 20
$filled = [math]::Max(0, [math]::Floor($contextPct * $barWidth / 100))
if ($contextPct -gt 0 -and $filled -eq 0) { $filled = 1 }
$empty = $barWidth - $filled

if ($contextPct -gt 75)       { $barColor = $bred }
elseif ($contextPct -gt 50)   { $barColor = $byellow }
else                          { $barColor = $bgreen }

$barFilled = "=" * $filled
$barEmpty  = "-" * $empty
$bar = "${barColor}${barFilled}${dim}${barEmpty}${rst}"
$pctStr = "$contextPct".PadLeft(3)

# 6. Format numbers
function Format-Num($n) {
    if ($n -ge 1000000) { return "$([math]::Round($n / 1000000, 1))M" }
    if ($n -ge 1000)    { return "$([math]::Round($n / 1000, 1))K" }
    return "$n"
}
$inputStr  = Format-Num $inputTokens
$outputStr = Format-Num $outputTokens
# Per-call token display (for line 2)
$callInStr  = Format-Num $curIn
$callOutStr = Format-Num $curOut
$contextSizeStr = Format-Num $contextSize

# Compute JSONL session delta (total - baseline at session start)
$jsonlSessionInput  = [Math]::Max(0, $jsonlInput  - $jsonlBaselineInput)
$jsonlSessionOutput = [Math]::Max(0, $jsonlOutput - $jsonlBaselineOutput)
$jsonlSessionCW     = [Math]::Max(0, $jsonlCW     - $jsonlBaselineCW)
$jsonlSessionCR     = [Math]::Max(0, $jsonlCR     - $jsonlBaselineCR)

$jsonlSessionCost = Calc-Cost $jsonlSessionInput $jsonlSessionOutput $jsonlSessionCW $jsonlSessionCR
$jsonlTotalCost   = Calc-Cost $jsonlInput $jsonlOutput $jsonlCW $jsonlCR
$subSessionCost   = [Math]::Max(0, $jsonlSessionCost - $sessionCost)

if ($jsonlEverScanned) {
    # 已扫描过，显示完整三值：主会话 / subagent / 项目总（含sub）
    $costThreshold = $jsonlTotalCost
    $costStr = "${currencySymbol}$($sessionCost.ToString('F3')) / ${currencySymbol}$($subSessionCost.ToString('F3')) / ${currencySymbol}$($jsonlTotalCost.ToString('F3'))"
} else {
    # 尚未扫描，用旧两值格式
    $costThreshold = [Math]::Max($cumulativeCost, $sessionCost)
    $costStr = "${currencySymbol}$($sessionCost.ToString('F3'))/${currencySymbol}$($cumulativeCost.ToString('F3'))"
}
$costColor = if ($costThreshold -ge 1.0) { $bred } elseif ($costThreshold -ge 0.5) { $byellow } else { $bgreen }

# 7. Build field map and order

$displayOrder = @('project', 'model', 'thinking', 'effort', 'bar', 'ctx', 'call', 'git', 'time', 'cost')

# Override from INI [display] section (captured during first INI parse above)
if ($orderFromIni) {
    $displayOrder = $orderFromIni -split '\s*,\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

$projectIcon = if ($isWorktree) { 'WT' } else { 'PR' }
$fields = [ordered]@{}
$fields['project']  = "${bold}${bcyan}[${projectIcon}] ${projectName}${rst}"
$fields['model']    = "${bmagenta}${modelDisplay}${rst}"
$fields['thinking'] = if ($thinkingIcon) { "${bcyan}${thinkingIcon}${rst}" } else { '' }
$fields['effort']   = if ($effortIcon)   { "${yellow}${effortIcon}${rst}" }      else { '' }
$fields['bar']      = "${bar} ${bold}${barColor}${pctStr}%${rst}"
$fields['ctx']      = "ctx: ${bwhite}${inputStr}/${outputStr}${rst} ${dim}/${bold}${barColor}${contextSizeStr}${rst}"
$fields['call']     = "call: ${bwhite}i${rst}${bwhite}${callInStr}${rst} ${bwhite}o${rst}${bwhite}${callOutStr}${rst}"

$gitField = ''
if ($gitBranch) {
    $gitField = "${cyan}git:${gitBranch}${rst}"
    if ($repoHost) { $gitField += " ${dim}@${repoHost}${rst}" }
}
$fields['git'] = $gitField

$fields['time'] = if ($durationStr) { "${bblue}time ${rst}${durationStr}" } else { '' }
$fields['cost'] = "${bold}${costColor}${costStr}${rst}"

$lineParts = foreach ($key in $displayOrder) {
    if ($fields.Contains($key) -and $fields[$key]) {
        $fields[$key]
    }
}
$line = $lineParts -join " ${dim}|${rst} "

# 8. Output
try {
    [Console]::WriteLine($line)
    [Console]::Out.Flush()
} catch {
    Write-Output "$modelDisplay | $projectName | $costStr | ${pctStr}%"
}

exit 0
