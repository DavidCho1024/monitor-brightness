Add-Type -AssemblyName System.Drawing
$script:BulbRows = @(
  '................',
  '.....OOOOOO.....',
  '...OOGGGGGGOO...',
  '..OGGHHGGGGGGO..',
  '..OGHGGGGGGGGO..',
  '.OGHGGGGGGGGGGO.',
  '.OGHGGGGGGGGGGO.',
  '.OGGGGGGGGGGGGO.',
  '.OGGGGFGGFGGGGO.',
  '..OGGGFGGFGGGO..',
  '..OGGGGFFGGGGO..',
  '...OGGGFFGGGO...',
  '....OGGFFGGO....',
  '....OGGFFGGO....',
  '.....BBBBBB.....',
  '.....DDDDDD.....',
  '.....BBBBBB.....',
  '......DDDD......',
  '................',
  '................')
$script:Rays = @(
  @(@(11,0),@(12,0),@(11,1),@(12,1)), @(@(5,2),@(6,3)), @(@(18,2),@(17,3)),
  @(@(1,9),@(2,9)), @(@(21,9),@(22,9)), @(@(2,14),@(3,13)), @(@(21,14),@(20,13)))
function Lerp-Color($a, $b, [double]$t) { [Drawing.Color]::FromArgb(255, [int]($a[0]+($b[0]-$a[0])*$t), [int]($a[1]+($b[1]-$a[1])*$t), [int]($a[2]+($b[2]-$a[2])*$t)) }
# 24x24 pixel-art bulb; lv 0 (off) .. 10 (full)
function New-BulbSprite([int]$lv) {
  $t = $lv / 10.0; $bmp = New-Object Drawing.Bitmap 24, 24; $ox = 4; $oy = 2
  $pal = @{
    'O' = [Drawing.Color]::FromArgb(255, 24, 20, 40)
    'G' = Lerp-Color @(96,96,112) @(252,224,56) $t
    'H' = Lerp-Color @(160,160,176) @(255,255,220) $t
    'F' = Lerp-Color @(56,56,68) @(255,120,24) $t
    'B' = [Drawing.Color]::FromArgb(255, 160, 164, 176)
    'D' = [Drawing.Color]::FromArgb(255, 88, 92, 108) }
  if ($lv -ge 5) {
    $glow = [Drawing.Color]::FromArgb([int](70 + ($lv - 5) * 37), 255, 236, 120)
    for ($y = 0; $y -le 13; $y++) { for ($x = 0; $x -lt 16; $x++) {
      if ($BulbRows[$y][$x] -ne '.') { continue }
      $n = $false
      foreach ($d in @(@(1,0),@(-1,0),@(0,1),@(0,-1))) { $nx = $x + $d[0]; $ny = $y + $d[1]
        if ($nx -ge 0 -and $nx -lt 16 -and $ny -ge 0 -and $ny -lt 20 -and $BulbRows[$ny][$nx] -eq 'O') { $n = $true } }
      if ($n) { $bmp.SetPixel($x + $ox, $y + $oy, $glow) } } } }
  for ($y = 0; $y -lt 20; $y++) { for ($x = 0; $x -lt 16; $x++) { $c = [string]$BulbRows[$y][$x]
    if ($c -ne '.') { $bmp.SetPixel($x + $ox, $y + $oy, $pal[$c]) } } }
  $rc = Lerp-Color @(200,150,0) @(255,232,40) $t
  $n = [math]::Round($lv * 7 / 10)
  for ($i = 0; $i -lt $n; $i++) { foreach ($p in $Rays[$i]) { $bmp.SetPixel($p[0], $p[1], $rc) } }
  return $bmp
}
