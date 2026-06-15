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
        # Back up existing ini before overwriting
        $dest = Join-Path $TargetDir $f.Name
        if ($f.Name -eq 'statusline.ini' -and (Test-Path $dest)) {
            $backup = Join-Path $TargetDir 'statusline.ini.bak'
            Copy-Item -Path $dest -Destination $backup -Force
            Write-Host "  BACKUP: statusline.ini → statusline.ini.bak"
        }
        Copy-Item -Path $f.From -Destination $TargetDir -Force
        Write-Host "  OK: $($f.Name)"
    } else {
        Write-Host "  WARN: $($f.Name) not found in repo — skipping"
    }
}

Write-Host "`n--- Configuring settings.json ---"
$settingsDir = Split-Path $TargetDir -Parent  # ~/.claude/
$settingsPath = Join-Path $settingsDir 'settings.json'
$commandPath = ($TargetDir.Replace('\', '/') + '/statusline.ps1')
$newStatusLine = @{
    type    = 'command'
    command = "powershell.exe -NoProfile -File `"$commandPath`""
    padding = 0
}

$settings = @{}
if (Test-Path $settingsPath) {
    try {
        $original = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $original) {
            $original.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
        }
    } catch { $settings = @{} }
}

if ($settings.ContainsKey('statusLine')) {
    $settings.Remove('statusLine')
    Write-Host "  Removed old statusLine entry"
}

$settings['statusLine'] = $newStatusLine

$settings | ConvertTo-Json -Depth 5 | Out-File -FilePath $settingsPath -Encoding UTF8
Write-Host "  Added statusLine entry to: $settingsPath"

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
