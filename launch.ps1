# Opens Focus Guard as a desktop app: starts the server if it isn't running,
# then shows the dashboard in its own window (Chrome or Edge "app" mode, no tabs).
$port = if ($env:FOCUS_GUARD_PORT) { $env:FOCUS_GUARD_PORT } else { 4747 }
$url = "http://localhost:$port"

# A port check, not an HTTP request: PowerShell's web cmdlets can stall on proxy auto-detection.
function Test-Up { [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) }

if (-not (Test-Up)) {
  & (Join-Path $PSScriptRoot 'start-hidden.ps1')
  for ($i = 0; $i -lt 30 -and -not (Test-Up); $i++) { Start-Sleep -Milliseconds 500 }
}

$browsers = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
)
$exe = $browsers | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($exe) {
  Start-Process $exe -ArgumentList "--app=$url", '--window-size=900,900'
} else {
  Start-Process $url
}
