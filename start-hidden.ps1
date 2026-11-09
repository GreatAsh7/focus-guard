# Starts Focus Guard with no console window (used by the Windows Startup shortcut).
# Output goes to focus-guard.log next to this file.
Set-Location $PSScriptRoot
$port = if ($env:FOCUS_GUARD_PORT) { $env:FOCUS_GUARD_PORT } else { 4747 }
if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) { return }  # already running
$log = Join-Path $PSScriptRoot 'focus-guard.log'
$node = (Get-Command node -ErrorAction Stop).Source
Start-Process -FilePath $node -ArgumentList '--env-file-if-exists=.env', 'server.js' `
  -WorkingDirectory $PSScriptRoot -WindowStyle Hidden `
  -RedirectStandardOutput $log -RedirectStandardError "$log.err"
