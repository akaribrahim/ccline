# ccline uninstaller — Windows (PowerShell).
#   ./uninstall.ps1
# Restores settings.json from the backup ccline made, or strips the
# statusLine key if there is no backup. Removes ccline.ps1 / ccline.conf.
$ErrorActionPreference = 'Stop'
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$settings  = Join-Path $claudeDir 'settings.json'
function Ok($m) { Write-Host "  $([char]0x2713) $m" -ForegroundColor Green }

if (Test-Path "$settings.ccline-bak") {
  Move-Item "$settings.ccline-bak" $settings -Force
  Ok 'restored settings.json from backup'
} elseif (Test-Path $settings) {
  try {
    $obj = Get-Content $settings -Raw | ConvertFrom-Json
    if ($obj.PSObject.Properties.Name -contains 'statusLine') {
      $obj.PSObject.Properties.Remove('statusLine')
      $obj | ConvertTo-Json -Depth 30 | Set-Content -Path $settings -Encoding UTF8
      Ok 'removed statusLine from settings.json'
    }
  } catch { }
}

Remove-Item (Join-Path $claudeDir 'ccline.ps1') -ErrorAction SilentlyContinue
Remove-Item (Join-Path $claudeDir 'ccline.conf') -ErrorAction SilentlyContinue
Ok 'removed ccline.ps1 and ccline.conf'
Write-Host '  ccline uninstalled.'
