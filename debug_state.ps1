param()

$projDir = "$env:USERPROFILE\.claude\projects\D--work-statusline"

Write-Output "=== Scanning project dir: $projDir ==="

# This is what the statusline actually scans
$jsseen = @{}
$totalIn=0; $totalOut=0; $totalCw=0; $totalCr=0; $mainCnt=0; $subCnt=0

Get-ChildItem "$projDir" -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue | ForEach-Object {
    $path = $_.FullName
    $isSub = ($path -match '\\subagents\\')
    Get-Content $path -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
        $line = $_.Trim(); if (-not $line) { return }
        try { $d = $line | ConvertFrom-Json } catch { return }
        if ($d.type -ne 'assistant') { return }
        $u = $d.message.usage; if (-not $u) { return }
        $ji = if ($null -ne $u.input_tokens) { [int]$u.input_tokens } else { 0 }
        $jo = if ($null -ne $u.output_tokens) { [int]$u.output_tokens } else { 0 }
        $jcw = if ($null -ne $u.cache_creation_input_tokens) { [int]$u.cache_creation_input_tokens } else { 0 }
        $jcr = if ($null -ne $u.cache_read_input_tokens) { [int]$u.cache_read_input_tokens } else { 0 }
        if ($ji -eq 0 -and $jo -eq 0 -and $jcw -eq 0 -and $jcr -eq 0) { return }
        $sig = "$($d.timestamp)|$ji|$jo"
        if ($jsseen.ContainsKey($sig)) { return }
        $jsseen[$sig] = $true
        $totalIn+=$ji; $totalOut+=$jo; $totalCw+=$jcw; $totalCr+=$jcr
        if ($isSub) { $subCnt++ } else { $mainCnt++ }
    }
}

Write-Output "Scan result:"
Write-Output "  Main msgs: $mainCnt, Sub msgs: $subCnt"
Write-Output "  input=$totalIn output=$totalOut cw=$totalCw cr=$totalCr"

# State comparison
$stateFile = "$env:USERPROFILE\.claude\statusline\statusline_state_D__work_statusline.json"
$state = Get-Content $stateFile -Encoding UTF8 | ConvertFrom-Json
Write-Output ""
Write-Output "State values:"
Write-Output "  jsonl_input=$($state.jsonl_input) (diff from fresh: $($totalIn - [int]$state.jsonl_input))"
Write-Output "  jsonl_baseline_input=$($state.jsonl_baseline_input)"
Write-Output "  session_input=$($state.session_input)"

$jsonlSesIn = [Math]::Max(0, [int]$state.jsonl_input - [int]$state.jsonl_baseline_input)
$subDeltaIn = [Math]::Max(0, $jsonlSesIn - [int]$state.session_input)
Write-Output ""
Write-Output "Session delta: jsonlIn=$jsonlSesIn, apiIn=$($state.session_input), subIn=$subDeltaIn"
Write-Output "  => sub input ratio: $(if ($jsonlSesIn -gt 0) { [math]::Round($subDeltaIn/$jsonlSesIn*100, 1) } else { 0 })% of JSONL session total"
