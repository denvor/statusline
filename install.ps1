# Install Claude Code statusline for Windows (PowerShell)
# Run from the repo root: powershell -File install.ps1
# Copies statusline.ps1 + statusline.ini to ~/.claude/
# Migrates old statusline_state.json to per-project files if needed
param(
    [string]$TargetDir = ''
)

if (-not $TargetDir) {
    $TargetDir = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.claude' } else { "$env:HOMEDRIVE$env:HOMEPATH\.claude" }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

# -------------------------------------------
# Step 1: Copy files
# -------------------------------------------
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Write-Host "Created: $TargetDir"
}

$files = @(
    @{Name="statusline.ps1"; From=Join-Path $scriptRoot 'statusline.ps1'},
    @{Name="statusline.ini"; From=Join-Path $scriptRoot 'statusline.ini'}
)

Write-Host "`n--- Installing to $TargetDir ---"
foreach ($f in $files) {
    if (Test-Path $f.From) {
        Copy-Item -Path $f.From -Destination $TargetDir -Force
        Write-Host "  OK: $($f.Name)"
    } else {
        Write-Host "  WARN: $($f.Name) not found in repo — skipping"
    }
}

Write-Host "`nMake sure your settings.json has the statusLine config:"
Write-Host '  "statusLine": {'
Write-Host '    "type": "command",'
Write-Host '    "command": "powershell.exe -NoProfile -File \"' + $TargetDir.Replace('\', '/') + '/statusline.ps1\"",'
Write-Host '    "padding": 0'
Write-Host '  }'

# -------------------------------------------
# Step 2: Migrate old state file
# -------------------------------------------
$oldPath = Join-Path $TargetDir 'statusline_state.json'

if (-not (Test-Path $oldPath)) {
    Write-Host "`nNo old state file to migrate."
    exit 0
}

Write-Host "`n--- Migrating old state file ---"
Write-Host "Reading: $oldPath"

$old = Get-Content $oldPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $old.projects) {
    Write-Host "No 'projects' key found — nothing to migrate."
    Write-Host "`nInstall complete!"
    exit 0
}

$count = 0
foreach ($prop in $old.projects.PSObject.Properties) {
    $projectKey = $prop.Name
    $data = $prop.Value

    $safeName = 'statusline_state_' + ($projectKey -replace '[:\\/]', '_') + '.json'
    $newPath = Join-Path $TargetDir $safeName

    if (Test-Path $newPath) {
        Write-Host "SKIP (already exists): $safeName"
        continue
    }

    $data | ConvertTo-Json -Depth 5 | Out-File -FilePath $newPath -Encoding UTF8 -NoNewline
    Write-Host "OK: $safeName"
    $count++
}

Write-Host "`nMigrated $count project(s)."
Write-Host "Old file kept at: $oldPath (delete manually if no longer needed)"
Write-Host "`nInstall complete!"
