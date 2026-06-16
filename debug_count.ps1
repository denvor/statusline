param()
$proj = "$env:USERPROFILE\.claude\projects\D--work-statusline\21291e78-1736-4bcd-81e6-563b2565b6e7"

# List all JSONL files
Write-Output "=== JSONL files in $proj ==="
Get-ChildItem "$proj" -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue | ForEach-Object {
    $f = $_
    $lineCnt = 0; $assistantCnt = 0; $usageCnt = 0
    Get-Content $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        $lineCnt++
        if ($line -match '"type"\s*:\s*"assistant"') { $assistantCnt++ }
        if ($line -match '"usage"') { $usageCnt++ }
    }
    Write-Output "$($f.Name): $lineCnt lines, $assistantCnt assistant, $usageCnt have usage"
}
