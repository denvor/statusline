# Migrate old statusline_state.json to per-project files
# Usage: powershell -File migrate_state.ps1
# Run from ~/.claude/ or pass the directory as argument

param(
    [string]$Dir = ''
)

if (-not $Dir) {
    $Dir = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.claude' } else { "$env:HOMEDRIVE$env:HOMEPATH\.claude" }
}

$oldPath = Join-Path $Dir 'statusline_state.json'

if (-not (Test-Path $oldPath)) {
    Write-Host "No old state file found: $oldPath"
    exit 0
}

Write-Host "Reading: $oldPath"
$old = Get-Content $oldPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $old.projects) {
    Write-Host "No 'projects' key found — nothing to migrate."
    exit 0
}

$count = 0
foreach ($prop in $old.projects.PSObject.Properties) {
    $projectKey = $prop.Name
    $data = $prop.Value

    $safeName = 'statusline_state_' + ($projectKey -replace '[:\\/]', '_') + '.json'
    $newPath = Join-Path $Dir $safeName

    # Check if target already exists
    if (Test-Path $newPath) {
        Write-Host "SKIP (already exists): $safeName"
        continue
    }

    # Write single-project JSON
    $data | ConvertTo-Json -Depth 5 | Out-File -FilePath $newPath -Encoding UTF8 -NoNewline
    Write-Host "OK: $safeName"
    $count++
}

Write-Host "`nMigrated $count project(s)."
Write-Host "Old file kept at: $oldPath (delete manually if no longer needed)"
