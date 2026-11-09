# Installs Focus Guard shortcuts:
#   Desktop + Start menu "Focus Guard"  -> click to open the app
#   Startup folder                      -> server starts hidden at login
# Run:  powershell -ExecutionPolicy Bypass -File install.ps1   (add -NoStartup to skip auto-start)
param([switch]$NoStartup)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$icon = Join-Path $dir 'focus-guard.ico'

if (-not (Test-Path $icon)) { & (Join-Path $dir 'make-icon.ps1') }

$ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$shell = New-Object -ComObject WScript.Shell
function New-Shortcut($path, $script) {
  $l = $shell.CreateShortcut($path)
  $l.TargetPath = $ps
  $l.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $dir $script)`""
  $l.WorkingDirectory = $dir
  $l.WindowStyle = 7
  $l.IconLocation = "$icon,0"
  $l.Description = 'Focus Guard'
  $l.Save()
  "Created $path"
}

New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Focus Guard.lnk') 'launch.ps1'
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'Focus Guard.lnk') 'launch.ps1'
if (-not $NoStartup) {
  New-Shortcut (Join-Path ([Environment]::GetFolderPath('Startup')) 'Focus Guard.lnk') 'start-hidden.ps1'
}
# Make Explorer pick up a changed icon right away.
& "$env:WINDIR\System32\ie4uinit.exe" -show
