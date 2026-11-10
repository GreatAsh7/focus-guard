# Draws the 1024 px iPhone app icon: same target-and-dart design as the desktop icon,
# but full-bleed and without transparency (iOS rounds the corners itself).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$s = 1024; $k = $s / 256.0
$bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$blue = [System.Drawing.Color]::FromArgb(255, 37, 76, 214)
$navy = [System.Drawing.Color]::FromArgb(255, 18, 32, 92)
$g.Clear($blue)

$c = 128 * $k
foreach ($ring in @(@(92, 'White'), @(70, $blue), @(48, 'White'), @(22, $navy))) {
  $rad = $ring[0] * $k
  $col = if ($ring[1] -is [string]) { [System.Drawing.Color]::FromName($ring[1]) } else { $ring[1] }
  $g.FillEllipse((New-Object System.Drawing.SolidBrush $col), $c - $rad, $c - $rad, 2 * $rad, 2 * $rad)
}

$pen = New-Object System.Drawing.Pen $navy, (14 * $k)
$pen.StartCap = 'Round'; $pen.EndCap = 'Round'
$g.DrawLine($pen, $c, $c, 206 * $k, 50 * $k)
$f = New-Object System.Drawing.Pen $navy, (11 * $k)
$f.StartCap = 'Round'; $f.EndCap = 'Round'
foreach ($t in @(@(206, 50), @(188, 68))) {
  $x = $t[0] * $k; $y = $t[1] * $k
  $g.DrawLine($f, $x, $y, $x + 28 * $k, $y + 6 * $k)
  $g.DrawLine($f, $x, $y, $x - 6 * $k, $y - 28 * $k)
}
$g.Dispose()

$out = Join-Path $PSScriptRoot 'App\Assets.xcassets\AppIcon.appiconset\icon-1024.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
"Wrote $out"
