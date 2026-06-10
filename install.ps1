# Install Claude Code statusline for Windows (PowerShell)
# Run from the repo root: powershell -File install.ps1
# Copies statusline.ps1 + statusline.ini to ~/.claude/statusline/
# Migrates existing statusline_state_*.json files from ~/.claude/ to subdirectory
param(
    [string]$TargetDir = ''
)

if (-not $TargetDir) {
    $TargetDir = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.claude\statusline' } else { "$env:HOMEDRIVE$env:HOMEPATH\.claude\statusline" }
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
# Step 2: Migrate state files to subdirectory
# -------------------------------------------
$oldDir = Split-Path $TargetDir -Parent  # ~/.claude/
$stateFiles = Get-ChildItem -Path $oldDir -Filter 'statusline_state_*.json' -File

if (-not $stateFiles) {
    Write-Host "`nNo state files to migrate."
} else {
    Write-Host "`n--- Migrating state files to $TargetDir ---"
    $count = 0
    foreach ($f in $stateFiles) {
        $dest = Join-Path $TargetDir $f.Name
        if (Test-Path $dest) {
            Write-Host "  SKIP (already exists): $($f.Name)"
        } else {
            Copy-Item -Path $f.FullName -Destination $dest -Force
            Write-Host "  OK: $($f.Name)"
            $count++
        }
    }
    Write-Host "Migrated $count state file(s)."
}

Write-Host "`nInstall complete!"
