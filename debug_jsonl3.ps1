param()

$proj = "$env:USERPROFILE\.claude\projects\D--work-statusline\21291e78-1736-4bcd-81e6-563b2565b6e7"

$jsseen = @{}
$totalIn = 0; $totalOut = 0; $totalCw = 0; $totalCr = 0; $totalCnt = 0
$subCnt = 0; $mainCnt = 0

# Scan all JSONL files recursively (exactly what statusline does)
Get-ChildItem "$proj" -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue | ForEach-Object {
    $isSub = $_.FullName -match '\\subagents\\'
    Get-Content $_.FullName -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
        $line = $_.Trim(); if (-not $line) { return }
        try { $d = $line | ConvertFrom-Json } catch { return }
        if ($d.type -ne 'assistant') { return }
        $u = $d.message.usage; if (-not $u) { return }
        $ji = if ($null -ne $u.input_tokens) { [int]$u.input_tokens } else { 0 }
        $jo = if ($null -ne $u.output_tokens) { [int]$u.output_tokens } else { 0 }
        $jcw_local = if ($null -ne $u.cache_creation_input_tokens) { [int]$u.cache_creation_input_tokens } else { 0 }
        $jcr_local = if ($null -ne $u.cache_read_input_tokens) { [int]$u.cache_read_input_tokens } else { 0 }
        if ($ji -eq 0 -and $jo -eq 0 -and $jcw_local -eq 0 -and $jcr_local -eq 0) { return }
        $sig = "$($d.timestamp)|$ji|$jo"
        if ($jsseen.ContainsKey($sig)) { return }
        $jsseen[$sig] = $true
        $totalIn += $ji; $totalOut += $jo
        $totalCw += $jcw_local; $totalCr += $jcr_local
        $totalCnt++
        if ($isSub) { $subCnt++ } else { $mainCnt++ }
    }
}
Write-Output "Fresh scan: total input=$totalIn, output=$totalOut, cr=$totalCr, msgs=$totalCnt (main=$mainCnt sub=$subCnt)"

# State comparison
$stateFile = "$env:USERPROFILE\.claude\statusline\statusline_state_D__work_statusline.json"
$state = Get-Content $stateFile -Encoding UTF8 | ConvertFrom-Json
Write-Output "State:     jsonl_input=$($state.jsonl_input), jsonl_output=$($state.jsonl_output)"

$diffIn = $totalIn - [int]$state.jsonl_input
$diffOut = $totalOut - [int]$state.jsonl_output
Write-Output "Difference (fresh - state): input=$diffIn, output=$diffOut"

Write-Output ""
Write-Output "=== Cost calculation (deepseek-v4-flash pricing) ==="
$baselineIn = [int]$state.jsonl_baseline_input
$baselineOut = [int]$state.jsonl_baseline_output
$baselineCr = [int]$state.jsonl_baseline_cache_read
$sesIn = [int]$state.session_input
$sesOut = [int]$state.session_output
$sesCr = [int]$state.session_cache_read

# Using the ALREADY SCANNED state values (as displayed by statusline)
$jsonlSesIn = [Math]::Max(0, [int]$state.jsonl_input - $baselineIn)
$jsonlSesOut = [Math]::Max(0, [int]$state.jsonl_output - $baselineOut)
$jsonlSesCr = [Math]::Max(0, [int]$state.jsonl_cache_read - $baselineCr)

$jsonlSesCost = ($jsonlSesIn/1e6)*1.0 + ($jsonlSesOut/1e6)*2.0 + ($jsonlSesCr/1e6)*0.02
$sesCost = ($sesIn/1e6)*1.0 + ($sesOut/1e6)*2.0 + ($sesCr/1e6)*0.02
$subCost = [Math]::Max(0, $jsonlSesCost - $sesCost)

Write-Output ("jsonlSessionCost:  ¥" + $jsonlSesCost.ToString('F3'))
Write-Output ("sessionCost:       ¥" + $sesCost.ToString('F3'))
Write-Output ("subSessionCost:    ¥" + $subCost.ToString('F3'))
