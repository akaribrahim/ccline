# ccline installer — Windows (PowerShell 5.1+ / pwsh 7+).
#
#   irm https://raw.githubusercontent.com/akaribrahim/ccline/main/install.ps1 | iex
#   # or from a clone:  ./install.ps1 -Style bars
#
# Idempotent. Backs up settings.json before touching it. Never deletes your
# old status line script — only repoints settings.json at ccline.
param(
  [ValidateSet('plain','bars','powerline','')]
  [string]$Style = ''
)
$ErrorActionPreference = 'Stop'

$repoRaw   = 'https://raw.githubusercontent.com/akaribrahim/ccline/main'
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$dest      = Join-Path $claudeDir 'ccline.ps1'
$conf      = Join-Path $claudeDir 'ccline.conf'
$settings  = Join-Path $claudeDir 'settings.json'

function Ok($m)   { Write-Host "  $([char]0x2713) $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }

Write-Host ''
Write-Host '  ccline — Claude Code status line'
Write-Host '  --------------------------------'
New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null

# 1) place the status line script (local clone first, else download) ---------
$selfDir = if ($PSScriptRoot) { $PSScriptRoot } else { '' }
$localSrc = if ($selfDir) { Join-Path $selfDir 'src/statusline.ps1' } else { '' }
if ($localSrc -and (Test-Path $localSrc)) {
  Copy-Item $localSrc $dest -Force
  Ok "installed from clone -> $dest"
} else {
  Invoke-WebRequest -Uri "$repoRaw/src/statusline.ps1" -OutFile $dest -UseBasicParsing
  Ok "downloaded -> $dest"
}

# 2) optional style ----------------------------------------------------------
if ($Style) {
  $lines = @()
  if (Test-Path $conf) { $lines = Get-Content $conf | Where-Object { $_ -notmatch '^\s*CCLINE_STYLE\s*=' } }
  $lines += "CCLINE_STYLE=$Style"
  Set-Content -Path $conf -Value $lines -Encoding UTF8
  Ok "style = $Style  (edit $conf to change)"
}

# 3) point settings.json at ccline (with backup) -----------------------------
$psHost = if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh' } else { 'powershell' }
$cmd = "$psHost -NoProfile -ExecutionPolicy Bypass -File `"$dest`""

# Back up only the *pre-ccline* settings: re-running the installer must not
# clobber that backup with a copy of our own config, or uninstall would have
# nothing real to restore.
if (Test-Path $settings) {
  if (Test-Path "$settings.ccline-bak") {
    Ok 'kept existing backup (settings.json.ccline-bak)'
  } else {
    Copy-Item $settings "$settings.ccline-bak"
    Ok 'backed up settings.json -> settings.json.ccline-bak'
  }
  try { $obj = Get-Content $settings -Raw | ConvertFrom-Json } catch { $obj = [pscustomobject]@{} }
} else {
  $obj = [pscustomobject]@{}
}
# refreshInterval re-runs the command every N seconds on top of Claude Code's
# event-driven updates. Without it the reset countdowns freeze and git state
# goes stale whenever the session sits idle.
$refresh = if ($env:CCLINE_REFRESH) { [int]$env:CCLINE_REFRESH } else { 10 }
$sl = [pscustomobject]@{ type = 'command'; command = $cmd; refreshInterval = $refresh }
if ($obj.PSObject.Properties.Name -contains 'statusLine') { $obj.statusLine = $sl }
else { $obj | Add-Member -NotePropertyName statusLine -NotePropertyValue $sl }
$obj | ConvertTo-Json -Depth 30 | Set-Content -Path $settings -Encoding UTF8
Ok "settings.json updated — refreshInterval ${refresh}s"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Warn 'git not on PATH — the git branch segment will be hidden.' }

Write-Host ''
Write-Host '  Done. Open a new Claude Code session to see it.'
Write-Host "  Config: $conf   Styles: plain | bars | powerline"
Write-Host '  Uninstall: restore settings.json.ccline-bak, or run uninstall.ps1'
Write-Host ''
