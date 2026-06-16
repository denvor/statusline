param()
$proj = "$env:USERPROFILE\.claude\projects\D--work-statusline\21291e78-1736-4bcd-81e6-563b2565b6e7"

# Main JSONL
$mainIn=0; $mainOut=0; $mainCw=0; $mainCr=0; $mainCnt=0
Get-Content "$proj\21291e78-1736-4bcd-81e6-563b2565b6e7.jsonl" -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
    $line = $_.Trim(); if (-not $line) { return }
    try { $d = $line | ConvertFrom-Json } catch { return }
    if ($d.type -ne 'assistant') { return }
    $u = $d.message.usage; if (-not $u) { return }
    $mainIn += if ($null -ne $u.input_tokens) { [int]$u.input_tokens } else { 0 }
    $mainOut += if ($null -ne $u.output_tokens) { [int]$u.output_tokens } else { 0 }
    $mainCw += if ($null -ne $u.cache_creation_input_tokens) { [int]$u.cache_creation_input_tokens } else { 0 }
    $mainCr += if ($null -ne $u.cache_read_input_tokens) { [int]$u.cache_read_input_tokens } else { 0 }
    $mainCnt++
}

# Subagents
$subIn=0; $subOut=0; $subCw=0; $subCr=0; $subCnt=0; $fileCnt=0
Get-ChildItem "$proj\subagents\*.jsonl" -ErrorAction SilentlyContinue | ForEach-Object {
    $fileCnt++
    Get-Content $_.FullName -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
        $line = $_.Trim(); if (-not $line) { return }
        try { $d = $line | ConvertFrom-Json } catch { return }
        if ($d.type -ne 'assistant') { return }
        $u = $d.message.usage; if (-not $u) { return }
        $subIn += if ($null -ne $u.input_tokens) { [int]$u.input_tokens } else { 0 }
        $subOut += if ($null -ne $u.output_tokens) { [int]$u.output_tokens } else { 0 }
        $subCw += if ($null -ne $u.cache_creation_input_tokens) { [int]$u.cache_creation_input_tokens } else { 0 }
        $subCr += if ($null -ne $u.cache_read_input_tokens) { [int]$u.cache_read_input_tokens } else { 0 }
        $subCnt++
    }
}

Write-Output "Main JSONL: $mainCnt assistant msgs, in=$mainIn, out=$mainOut, cw=$mainCw, cr=$mainCr"
Write-Output "Subagents:  $subCnt assistant msgs in $fileCnt files, in=$subIn, out=$subOut, cw=$subCw, cr=$subCr"
$totalIn = $mainIn + $subIn; $totalOut = $mainOut + $subOut
Write-Output "Total: in=$totalIn, out=$totalOut"

# State file
$stateFile = "$env:USERPROFILE\.claude\statusline\statusline_state_D__work_statusline.json"
$state = Get-Content $stateFile -Encoding UTF8 | ConvertFrom-Json
Write-Output "---"
Write-Output "State: jsonl_input=$($state.jsonl_input), jsonl_output=$($state.jsonl_output)"
Write-Output "State: jsonl_baseline_input=$($state.jsonl_baseline_input), jsonl_baseline_output=$($state.jsonl_baseline_output)"
Write-Output "State: jsonl_scan_count=$($state.jsonl_scan_count)"
$deltaInput = [Math]::Max(0, [int]$state.jsonl_input - [int]$state.jsonl_baseline_input)
$deltaOutput = [Math]::Max(0, [int]$state.jsonl_output - [int]$state.jsonl_baseline_output)
Write-Output "JSONL session delta: in=$deltaInput, out=$deltaOutput"
Write-Output "API session: in=$($state.session_input), out=$($state.session_output)"
$subInDelta = [Math]::Max(0, $deltaInput - [int]$state.session_input)
$subOutDelta = [Math]::Max(0, $deltaOutput - [int]$state.session_output)
Write-Output "Subagent delta (JSONL - API): in=$subInDelta, out=$subOutDelta"
