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
$modelDisplay = switch -Regex ($modelRaw) {
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
    default               { $modelRaw }
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
$iniPath   = Join-Path $scriptDir '.claude/statusline.ini'
$statePath = Join-Path $scriptDir '.claude/statusline_state.json'

# Default pricing (DeepSeek V4, CNY) — used if INI is missing or invalid
$pricing = @{
    input_price       = 2.00
    output_price      = 8.00
    cache_write_price = 2.00
    cache_read_price  = 0.50
    currency          = 'CNY'
}

# Try to read INI file (section-based: [model_name] -> pricing)
$iniSections = @{}
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
                }
            }
        }
    } catch {}
}

# Match pricing to current model, fallback to [default]
$matchedSection = if ($iniSections.ContainsKey($modelRaw)) { $modelRaw } else { 'default' }
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

$cumIn = 0; $cumOut = 0; $cumCW = 0; $cumCR = 0

# Read existing state
$state = $null
if (Test-Path $statePath) {
    try {
        $rawState = [System.IO.File]::ReadAllText($statePath, [System.Text.UTF8Encoding]::new($false))
        $state = $rawState | ConvertFrom-Json
    } catch {}
}

# Check if session changed or new
$isNewSession = (-not $state) -or ($state.session_id -ne $sessionId)

if ($isNewSession) {
    # New session — start fresh
    $cumIn = $curIn; $cumOut = $curOut; $cumCW = $curCW; $cumCR = $curCR
} else {
    # Same session — check for duplicate (debounce)
    $lastIn  = if ($state.last_input)  { [int]$state.last_input }  else { 0 }
    $lastOut = if ($state.last_output) { [int]$state.last_output } else { 0 }
    $lastCW  = if ($state.last_cache_write) { [int]$state.last_cache_write } else { 0 }
    $lastCR  = if ($state.last_cache_read)  { [int]$state.last_cache_read }  else { 0 }

    $isDuplicate = ($curIn -eq $lastIn) -and ($curOut -eq $lastOut) -and
                   ($curCW -eq $lastCW) -and ($curCR -eq $lastCR)

    $cumIn  = if ($state.cumulative_input)  { [int]$state.cumulative_input }  else { 0 }
    $cumOut = if ($state.cumulative_output) { [int]$state.cumulative_output } else { 0 }
    $cumCW  = if ($state.cumulative_cache_write) { [int]$state.cumulative_cache_write } else { 0 }
    $cumCR  = if ($state.cumulative_cache_read)  { [int]$state.cumulative_cache_read }  else { 0 }

    if (-not $isDuplicate -and ($curIn + $curOut + $curCW + $curCR) -gt 0) {
        $cumIn  += $curIn
        $cumOut += $curOut
        $cumCW  += $curCW
        $cumCR  += $curCR
    }
}

# Save state
try {
    $stateJson = @{
        session_id            = $sessionId
        cumulative_input      = $cumIn
        cumulative_output     = $cumOut
        cumulative_cache_write = $cumCW
        cumulative_cache_read  = $cumCR
        last_input            = $curIn
        last_output           = $curOut
        last_cache_write      = $curCW
        last_cache_read       = $curCR
    } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($statePath, $stateJson, [System.Text.UTF8Encoding]::new($false))
} catch {}

# --- Calculate cost from custom pricing ---
$costValue = 0.0
$costValue += ($cumIn  / 1000000.0) * $pricing['input_price']
$costValue += ($cumOut / 1000000.0) * $pricing['output_price']
$costValue += ($cumCW  / 1000000.0) * $pricing['cache_write_price']
$costValue += ($cumCR  / 1000000.0) * $pricing['cache_read_price']

# Fallback to Claude Code's built-in cost if our calculation is 0 but CC reports cost
if ($costValue -eq 0.0 -and $data.cost.total_cost_usd) {
    $costValue = [double]$data.cost.total_cost_usd
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
$durationStr = Format-Duration $data.cost.total_duration_ms

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

# Worktree?
$isWorktree = ($data.worktree.name -or $data.workspace.git_worktree)

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

if ($contextPct -gt 75)       { $barColor = $bred;    $pctColor = $bred }
elseif ($contextPct -gt 50)   { $barColor = $byellow; $pctColor = $byellow }
else                          { $barColor = $bgreen;  $pctColor = $bgreen }

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
$tokenColor = if ($contextPct -gt 75) { $bred } else { $dim }

# Per-call token display (for line 2)
$callInStr  = Format-Num $curIn
$callOutStr = Format-Num $curOut

if ($costValue -ge 1.0)       { $costColor = $bred }
elseif ($costValue -ge 0.5)   { $costColor = $byellow }
else                          { $costColor = $bgreen }
$costStr = "${currencySymbol}$($costValue.ToString('F3'))"

# 7. Build output line (single line, cost at end)

$line = ''
$projectIcon = if ($isWorktree) { 'WT' } else { 'PR' }
$line += "${bold}${bcyan}[${projectIcon}] ${projectName}${rst}"
$line += " ${dim}|${rst} "
$line += "${bmagenta}${modelDisplay}${rst}"
if ($thinkingIcon) { $line += " ${bcyan}${thinkingIcon}${rst}" }
if ($effortIcon)   { $line += " ${yellow}${effortIcon}${rst}" }
$line += " ${dim}|${rst} "
$line += "${bar} ${bold}${pctColor}${pctStr}%${rst}"
$line += " ${dim}|${rst} "
$line += "ctx: ${bwhite}${inputStr}/${outputStr}${rst}"
$contextSizeStr = Format-Num $contextSize
$line += " ${dim}/${bold}${pctColor}${contextSizeStr}${rst}"
$line += " ${dim}|${rst} "
$line += "call: ${bwhite}i${rst}${bwhite}${callInStr}${rst} ${bwhite}o${rst}${bwhite}${callOutStr}${rst}"

if ($gitBranch) {
    $line += " ${dim}|${rst} "
    $line += "${cyan}git:${gitBranch}${rst}"
}
if ($repoHost) {
    $line += " ${dim}@${repoHost}${rst}"
}

if ($durationStr) {
    $line += " ${dim}|${rst} "
    $line += "${bblue}time ${rst}${durationStr}"
}

$line += " ${dim}|${rst} "
$line += "${bold}${costColor}${costStr}${rst}"

# 8. Output
try {
    [Console]::WriteLine($line)
    [Console]::Out.Flush()
} catch {
    Write-Output "$modelDisplay | $projectName | $costStr | ${pctStr}%"
}

exit 0
