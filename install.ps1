# Install statusline — simplified stdin-only statusline for Windows (PowerShell)
# Run: powershell -File install.ps1
# Copies statusline.ps1 to ~/.claude/statusline/ and updates settings.json
param(
    [string]$TargetDir = ''
)

if (-not $TargetDir) {
    $TargetDir = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.claude\statusline' } else { "$env:HOMEDRIVE$env:HOMEPATH\.claude\statusline" }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

# -------------------------------------------
# Step 1: Copy statusline.ps1
# -------------------------------------------
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Write-Host "Created: $TargetDir"
}

Write-Host "`n--- Installing to $TargetDir ---"

$source = Join-Path $scriptRoot 'statusline.ps1'
if (Test-Path $source) {
    Copy-Item -Path $source -Destination $TargetDir -Force
    Write-Host "  OK: statusline.ps1"
} else {
    Write-Host "  ERROR: statusline.ps1 not found in repo!"
    exit 1
}

# statusline.ini is shared with slineplus
$iniDest = Join-Path $TargetDir 'statusline.ini'
if (Test-Path $iniDest) {
    Write-Host "  SKIP: statusline.ini (already exists)"
} else {
    $iniSource = Join-Path $scriptRoot 'statusline.ini'
    if (Test-Path $iniSource) {
        Copy-Item -Path $iniSource -Destination $TargetDir -Force
        Write-Host "  OK: statusline.ini"
    } else {
        Write-Host "  WARN: statusline.ini not found — statusline will use defaults"
    }
}

# -------------------------------------------
# Step 2: Configure settings.json
# -------------------------------------------
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
Write-Host "  Added statusLine entry → statusline.ps1"

Write-Host "`nInstall complete! Restart Claude Code to see statusline."
