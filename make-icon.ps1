# Draws the Focus Guard icon (blue tile, white target, arrow in the bullseye)
# and writes focus-guard.ico (16-256 px) plus public/icon.png for the dashboard.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$dir = $PSScriptRoot

function New-IconBitmap([int]$s) {
  $bmp = New-Object System.Drawing.Bitmap $s, $s
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.Clear([System.Drawing.Color]::Transparent)
  $k = $s / 256.0
  $blue = [System.Drawing.Color]::FromArgb(255, 37, 76, 214)
  $navy = [System.Drawing.Color]::FromArgb(255, 18, 32, 92)

  # Rounded-square tile
  $r = 56 * $k; $p = 6 * $k; $w = $s - 2 * $p
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddArc($p, $p, 2 * $r, 2 * $r, 180, 90)
  $path.AddArc($p + $w - 2 * $r, $p, 2 * $r, 2 * $r, 270, 90)
  $path.AddArc($p + $w - 2 * $r, $p + $w - 2 * $r, 2 * $r, 2 * $r, 0, 90)
  $path.AddArc($p, $p + $w - 2 * $r, 2 * $r, 2 * $r, 90, 90)
  $path.CloseFigure()
  $g.FillPath((New-Object System.Drawing.SolidBrush $blue), $path)

  # Target: white ring, blue ring, white ring, navy bullseye
  $c = 128 * $k
  foreach ($ring in @(@(92, 'White'), @(70, $blue), @(48, 'White'), @(22, $navy))) {
    $rad = $ring[0] * $k
    $col = if ($ring[1] -is [string]) { [System.Drawing.Color]::FromName($ring[1]) } else { $ring[1] }
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $col), $c - $rad, $c - $rad, 2 * $rad, 2 * $rad)
  }

  # Arrow from the top-right into the bullseye (skipped at 16 px, where it turns to mush)
  if ($s -ge 24) {
    $pen = New-Object System.Drawing.Pen $navy, ([Math]::Max(2, 14 * $k))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $g.DrawLine($pen, $c, $c, 206 * $k, 50 * $k)
    # Two pairs of fletching at the tail, flaring away from the target
    $f = New-Object System.Drawing.Pen $navy, ([Math]::Max(2, 11 * $k))
    $f.StartCap = 'Round'; $f.EndCap = 'Round'
    foreach ($t in @(@(206, 50), @(188, 68))) {
      $x = $t[0] * $k; $y = $t[1] * $k
      $g.DrawLine($f, $x, $y, $x + 28 * $k, $y + 6 * $k)
      $g.DrawLine($f, $x, $y, $x - 6 * $k, $y - 28 * $k)
    }
  }
  $g.Dispose()
  return $bmp
}

$sizes = 16, 24, 32, 48, 64, 128, 256
$images = foreach ($s in $sizes) {
  $ms = New-Object System.IO.MemoryStream
  (New-IconBitmap $s).Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  , $ms.ToArray()
}

# ICO container: header, one directory entry per size, then the PNG images.
$fs = [System.IO.File]::Create((Join-Path $dir 'focus-guard.ico'))
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $dim = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
  $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
  $w.Write([uint16]1); $w.Write([uint16]32)
  $w.Write([uint32]$images[$i].Length); $w.Write([uint32]$offset)
  $offset += $images[$i].Length
}
foreach ($img in $images) { $w.Write($img) }
$w.Close()

(New-IconBitmap 256).Save((Join-Path $dir 'public\icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
"Wrote focus-guard.ico and public\icon.png"
