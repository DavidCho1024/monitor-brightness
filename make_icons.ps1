$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $dir 'pixel.ps1')
foreach ($lv in 0..10) {
  $sp = New-BulbSprite $lv; $pngs = @()
  foreach ($sz in 24, 48, 72, 96, 256) {
    $b = New-Object Drawing.Bitmap $sz, $sz; $g = [Drawing.Graphics]::FromImage($b)
    $g.InterpolationMode = 'NearestNeighbor'; $g.PixelOffsetMode = 'Half'
    $k = [math]::Floor($sz / 24); $o = [int](($sz - 24 * $k) / 2)
    $g.DrawImage($sp, $o, $o, 24 * $k, 24 * $k); $g.Dispose()
    $ms = New-Object IO.MemoryStream; $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $pngs += ,@($sz, $ms.ToArray())
  }
  $w = New-Object IO.BinaryWriter ([IO.File]::Create((Join-Path $dir ("bulb_{0}.ico" -f ($lv * 10)))))
  $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$pngs.Count)
  $off = 6 + 16 * $pngs.Count
  foreach ($p in $pngs) { $d = if ($p[0] -ge 256) { 0 } else { $p[0] }
    $w.Write([byte]$d); $w.Write([byte]$d); $w.Write([byte]0); $w.Write([byte]0); $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$p[1].Length); $w.Write([uint32]$off); $off += $p[1].Length }
  foreach ($p in $pngs) { $w.Write($p[1]) }
  $w.Close()
  if ($lv -in 0, 5, 10) { $b = New-Object Drawing.Bitmap 240, 240; $g = [Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'NearestNeighbor'; $g.PixelOffsetMode = 'Half'; $g.Clear([Drawing.Color]::FromArgb(40,40,60)); $g.DrawImage($sp, 0, 0, 240, 240); $b.Save((Join-Path $env:TEMP "px$lv.png")) }
}
Copy-Item (Join-Path $dir 'bulb_100.ico') (Join-Path $dir 'bulb_on.ico') -Force
Copy-Item (Join-Path $dir 'bulb_0.ico') (Join-Path $dir 'bulb_off.ico') -Force
'icons ok'
