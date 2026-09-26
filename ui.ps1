param([int]$Apply = -1)
$ErrorActionPreference = 'SilentlyContinue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
. (Join-Path $dir 'pixel.ps1')
$presetFile = Join-Path $dir 'presets.json'
$AppId = 'PixelBrightness.App'
# UI language (ko / en): saved choice, otherwise follow Windows
$langFile = Join-Path $dir 'lang.txt'
$script:lang = if (Test-Path $langFile) { (Get-Content $langFile -Raw).Trim() } elseif ((Get-Culture).TwoLetterISOLanguageName -eq 'ko') { 'ko' } else { 'en' }
function L($ko, $en) { if ($script:lang -eq 'ko') { $ko } else { $en } }

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class G {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DD { public int cb; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Name; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Str; public int Flags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Id; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Key; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevices(string dev, uint i, ref DD dd, uint f);
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateDC(string drv, string dev, string o, IntPtr m);
  [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr h);
  [DllImport("gdi32.dll")] static extern bool SetDeviceGammaRamp(IntPtr h, ushort[] r);
  [DllImport("shell32.dll")] public static extern void SHChangeNotify(int e, uint f, IntPtr a, IntPtr b);
  [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool ReleaseCapture();
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  // External monitors (not built-in panels, whose ids are in skip): dim via gamma ramp; clamps to the darkest level Windows allows
  public static void Set(int pct, string[] skip) {
    for (uint i = 0; ; i++) { var a = new DD(); a.cb = Marshal.SizeOf(a); if (!EnumDisplayDevices(null, i, ref a, 0)) break;
      if ((a.Flags & 1) == 0) continue;
      var m = new DD(); m.cb = Marshal.SizeOf(m); if (!EnumDisplayDevices(a.Name, 0, ref m, 0)) continue;
      bool builtIn = false; foreach (var s in skip) if (s.Length > 0 && m.Id.Contains(s)) builtIn = true;
      if (builtIn) continue;
      IntPtr dc = CreateDC(null, a.Name, null, IntPtr.Zero);
      for (int p = pct; p <= 100; p += 5) { var r = new ushort[768];
        for (int k = 0; k < 256; k++) { int v = k * 256 * p / 100; if (v > 65535) v = 65535; r[k] = r[k+256] = r[k+512] = (ushort)v; }
        if (SetDeviceGammaRamp(dc, r)) break; }
      DeleteDC(dc); } } }
'@
# Own taskbar identity, so the window shows our bulb instead of the PowerShell icon
[G]::SetCurrentProcessExplicitAppUserModelID($AppId) | Out-Null
[G]::SetProcessDPIAware() | Out-Null

$wmi = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods
# Built-in panels (laptop screens) get real backlight control; everything else uses the gamma fallback
$internal = [string[]]@(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorConnectionParams | Where-Object { $_.VideoOutputTechnology -eq 2147483648 } | ForEach-Object { $_.InstanceName.Split('\')[1] })
if (-not $internal) { $internal = [string[]]@() }
function Set-Bright([int]$pct) {
  foreach ($m in $wmi) { Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{Timeout=1; Brightness=[byte]$pct} | Out-Null }
  [G]::Set($pct, $internal)
}
function Icon-Path([int]$pct) { Join-Path $dir ('bulb_{0}.ico' -f ([math]::Round($pct / 10) * 10)) }
function Update-Icon([int]$pct) {
  Set-Content (Join-Path $dir 'state.txt') $pct
  $ws = New-Object -ComObject WScript.Shell
  # Any shortcut on the desktop or pinned to the taskbar that launches this tool, whatever it was renamed to
  $lnks = @(Get-ChildItem ([Environment]::GetFolderPath('Desktop')), (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar') -Filter *.lnk -ErrorAction SilentlyContinue |
    Where-Object { $ws.CreateShortcut($_.FullName).Arguments -like "*$(Join-Path $dir 'launch.vbs')*" } | ForEach-Object { $_.FullName })
  foreach ($l in $lnks) { $sc = $ws.CreateShortcut($l); $sc.IconLocation = (Icon-Path $pct) + ',0'; $sc.Save() }
  & (Join-Path $dir 'set_appid.ps1') -AppId $AppId -Paths $lnks | Out-Null
  # Tell the shell each shortcut changed (SHCNE_UPDATEITEM), then flush the icon cache so the taskbar pin redraws
  foreach ($l in $lnks) { $p = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($l); [G]::SHChangeNotify(0x2000, 0x5, $p, [IntPtr]::Zero); [Runtime.InteropServices.Marshal]::FreeHGlobal($p) }
  [G]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
  Start-Process "$env:WINDIR\System32\ie4uinit.exe" -ArgumentList '-show' -WindowStyle Hidden
}

# ---------- taskbar right-click list (saved settings) ----------
Add-Type -Path (Join-Path $dir 'jumplist.cs')
# Desktop icon right-click: same saved settings, shown only on the "Monitor Brightness" shortcut
function Update-DesktopMenu($p) {
  $base = 'HKCU:\Software\Classes\lnkfile\shell'
  for ($i = 0; $i -lt 3; $i++) {
    $k = "$base\BrightnessPreset$($i+1)"
    if ($p[$i] -eq $null) { Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue; continue }
    New-Item "$k\command" -Force | Out-Null
    Set-ItemProperty $k -Name 'MUIVerb' -Value "$($i+1)P  $(L '밝기' 'Brightness') $($p[$i])%"
    Set-ItemProperty $k -Name 'Icon' -Value (Icon-Path $p[$i])
    Set-ItemProperty $k -Name 'AppliesTo' -Value 'System.ItemNameDisplay:~~"Monitor Brightness"'
    Set-ItemProperty $k -Name 'Position' -Value 'Top'
    Set-ItemProperty "$k\command" -Name '(default)' -Value "`"$env:WINDIR\System32\wscript.exe`" `"$(Join-Path $dir 'launch.vbs')`" $($p[$i])"
  }
}
function Update-JumpList {
  $p = @($null, $null, $null)
  if (Test-Path $presetFile) { $j = Get-Content $presetFile -Raw | ConvertFrom-Json; for ($i = 0; $i -lt 3; $i++) { if ($j[$i] -ne $null) { $p[$i] = [int]$j[$i] } } }
  $t = @(); $a = @(); $ic = @()
  for ($i = 0; $i -lt 3; $i++) { if ($p[$i] -eq $null) { continue }
    $t += "$($i+1)P  $(L '밝기' 'Brightness') $($p[$i])%"; $a += "`"$(Join-Path $dir 'launch.vbs')`" $($p[$i])"; $ic += (Icon-Path $p[$i]) }
  Update-DesktopMenu $p
  [JumpList]::Set($AppId, "$env:WINDIR\System32\wscript.exe", [string[]]$t, [string[]]$a, [string[]]$ic)
}

# Keeps a single, correctly named shortcut. Windows sometimes leaves the old file behind when you unpin,
# so the next pin becomes "... (2)". Leftovers the taskbar no longer references are removed here.
function Repair-Shortcuts {
  $ws = New-Object -ComObject WScript.Shell
  $canon = 'Monitor Brightness.lnk'
  $mine = { param($folder) Get-ChildItem $folder -Filter *.lnk -ErrorAction SilentlyContinue |
    Where-Object { $ws.CreateShortcut($_.FullName).Arguments -like "*$(Join-Path $dir 'launch.vbs')*" } }

  $desk = [Environment]::GetFolderPath('Desktop')
  $d = @(& $mine $desk)
  if ($d.Count -gt 0) {
    $keep = $d | Where-Object { $_.Name -eq $canon } | Select-Object -First 1
    if (-not $keep) { $keep = Rename-Item $d[0].FullName $canon -PassThru }
    $d | Where-Object { $_.FullName -ne $keep.FullName } | Remove-Item -ErrorAction SilentlyContinue
  }

  $pinDir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
  $fav = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -ErrorAction SilentlyContinue).Favorites
  if ($fav) {
    $u = [Text.Encoding]::Unicode
    $blob = $u.GetString($fav) + $u.GetString($fav, 1, $fav.Length - 1)
    & $mine $pinDir | Where-Object { -not $blob.Contains($_.Name) } | Remove-Item -ErrorAction SilentlyContinue
  }
}
Repair-Shortcuts

# Quick mode from the right-click list: apply a level and exit without showing the window
if ($Apply -ge 0) { Set-Bright $Apply; Update-Icon $Apply; return }

# ---------- sound (8-bit square wave blips) ----------
function New-Beep([int[]]$freqs, [int]$ms) {
  $rate = 11025; $per = [int]($rate * $ms / 1000); $n = $per * $freqs.Count
  $st = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $st
  $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $n)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
  $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]$rate); $w.Write([int16]1); $w.Write([int16]8)
  $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$n)
  $buf = New-Object byte[] $n
  for ($j = 0; $j -lt $freqs.Count; $j++) { $half = $rate / $freqs[$j] / 2
    for ($i = 0; $i -lt $per; $i++) { $buf[$j * $per + $i] = if ([math]::Floor($i / $half) % 2) { 104 } else { 152 } } }
  $w.Write($buf); $st.Position = 0
  $p = New-Object Media.SoundPlayer $st; $p.Load(); $p
}
$sndMove = New-Beep @(1568) 18
$sndOk = New-Beep @(988, 1319, 1976) 70
$sndSave = New-Beep @(784, 1175) 60
$sndLoad = New-Beep @(1175, 1568) 45
$sndCancel = New-Beep @(523, 392) 70
$beepWatch = [Diagnostics.Stopwatch]::StartNew()
$soundFile = Join-Path $dir 'sound.txt'
$script:sound = -not ((Test-Path $soundFile) -and (Get-Content $soundFile -Raw).Trim() -eq 'off')
function Snd($p, [switch]$Sync) { if (-not $script:sound) { return }; if ($Sync) { $p.PlaySync() } else { $p.Play() } }

# ---------- state ----------
$presets = @($null, $null, $null)
if (Test-Path $presetFile) { $j = Get-Content $presetFile -Raw | ConvertFrom-Json; for ($i = 0; $i -lt 3; $i++) { if ($j[$i] -ne $null) { $presets[$i] = [int]$j[$i] } } }
$cur = (Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness | Select-Object -First 1).CurrentBrightness
$script:val = if ($cur -ne $null) { [int]$cur } else { 100 }
$script:applied = $script:val
$script:hover = ''; $script:drag = $false; $script:pending = $false; $script:blink = $true
$script:toastSlot = -1; $script:toastUntil = [datetime]::MinValue
$sprites = @(0..10 | ForEach-Object { New-BulbSprite $_ })

# ---------- pixel canvas ----------
$W = 240; $H = 176
$dpi = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX
$Scale = [math]::Max(2, [math]::Floor(3 * $dpi / 96))
$canvas = New-Object Drawing.Bitmap $W, $H
$font = New-Object Drawing.Font 'Gulim', 12, ([Drawing.GraphicsUnit]::Pixel)
$sf = [Drawing.StringFormat]::GenericTypographic
function C($r, $g, $b) { [Drawing.Color]::FromArgb(255, $r, $g, $b) }
$cBg = C 14 14 38; $cStar = C 90 90 150; $cWhite = C 248 248 248; $cBlack = C 0 0 0
$cDim = C 120 120 168; $cYellow = C 252 216 64; $cEmpty = C 44 44 70; $cRed = C 228 60 88; $cHot = C 60 40 0
$rects = [ordered]@{
  close  = @(222, 7, 12, 11)
  sound  = @(10, 6, 34, 13)
  lang   = @(198, 6, 22, 13)
  bar    = @(28, 84, 184, 14)
  slot0  = @(20, 108, 60, 16);  save0 = @(20, 127, 60, 13)
  slot1  = @(90, 108, 60, 16);  save1 = @(90, 127, 60, 13)
  slot2  = @(160, 108, 60, 16); save2 = @(160, 127, 60, 13)
  apply  = @(54, 150, 62, 15);  cancel = @(124, 150, 62, 15)
}
$stars = @(1..28 | ForEach-Object { ,@((Get-Random -Min 2 -Max 238), (Get-Random -Min 2 -Max 174), (Get-Random -Min 0 -Max 2)) })
$digits = @{
  '0'='111101101101111'; '1'='010110010010111'; '2'='111001111100111'; '3'='111001111001111'; '4'='101101111001001'
  '5'='111100111001111'; '6'='111100111101111'; '7'='111001001001001'; '8'='111101111101111'; '9'='111101111001111'; '%'='101001010100101' }

function Px($g, $c, $x, $y, $w, $h) { $b = New-Object Drawing.SolidBrush $c; $g.FillRectangle($b, [int]$x, [int]$y, [int]$w, [int]$h); $b.Dispose() }
function Box($g, $r, $border, $fill) {
  $x, $y, $w, $h = $r
  Px $g $border ($x + 1) $y ($w - 2) $h; Px $g $border $x ($y + 1) $w ($h - 2)
  Px $g $fill ($x + 2) ($y + 2) ($w - 4) ($h - 4)
}
function Txt($g, $s, $x, $y, $c, [switch]$Center) {
  if ($Center) { $x = $x - [math]::Round($g.MeasureString($s, $font, 1000, $sf).Width / 2) }
  $b = New-Object Drawing.SolidBrush $c; $g.DrawString($s, $font, $b, [single]$x, [single]$y, $sf); $b.Dispose()
}
function Big($g, $s, $x, $y, $k, $c) {
  foreach ($ch in $s.ToCharArray()) { $m = $digits[[string]$ch]
    for ($i = 0; $i -lt 15; $i++) { if ($m[$i] -eq '1') { Px $g $c ($x + ($i % 3) * $k) ($y + [math]::Floor($i / 3) * $k) $k $k } }
    $x += 4 * $k }
}
function Arrow($g, $x, $y, $c) { Px $g $c $x $y 1 7; Px $g $c ($x + 1) ($y + 1) 1 5; Px $g $c ($x + 2) ($y + 2) 1 3; Px $g $c ($x + 3) ($y + 3) 1 1 }

function Render {
  $g = [Drawing.Graphics]::FromImage($canvas)
  $g.TextRenderingHint = 'SingleBitPerPixelGridFit'; $g.InterpolationMode = 'NearestNeighbor'; $g.PixelOffsetMode = 'Half'
  $g.Clear($cBg)
  foreach ($st in $stars) { if ($st[2] -eq 0 -or $script:blink) { Px $g $cStar $st[0] $st[1] 1 1 } }
  Box $g @(4, 4, 232, 168) $cWhite $cBlack
  Txt $g 'MONITOR BRIGHTNESS' 120 8 $cYellow -Center
  Txt $g 'x' 226 7 $(if ($script:hover -eq 'close') { $cRed } else { $cDim })
  $sc = if ($script:hover -eq 'sound') { $cYellow } elseif ($script:sound) { $cWhite } else { $cDim }
  Txt $g $(if ($script:sound) { '♪ON' } else { '♪OFF' }) 12 7 $sc
  Txt $g $(if ($script:lang -eq 'ko') { '한' } else { 'EN' }) 209 7 $(if ($script:hover -eq 'lang') { $cYellow } else { $cWhite }) -Center
  Px $g $cWhite 8 21 224 1

  # bulb + big number, centered as one group
  $lv = [int][math]::Round($script:val / 10)
  $num = "$($script:val)%"; $nw = $num.Length * 20 - 5; $gx = [int]((240 - (48 + 14 + $nw)) / 2)
  $g.DrawImage($sprites[$lv], $gx, 26, 48, 48)
  Big $g $num ($gx + 62) 38 5 $cWhite

  # segmented bar
  Box $g $rects.bar $(if ($script:hover -eq 'bar' -or $script:drag) { $cYellow } else { $cWhite }) $cBlack
  $filled = [math]::Ceiling($script:val / 5)
  for ($i = 0; $i -lt 20; $i++) {
    $c = if ($i -lt $filled) { Lerp-Color @(60,80,220) @(252,216,64) ($i / 19) } else { $cEmpty }
    Px $g $c (30 + $i * 9) 86 8 10 }
  $cx = 30 + [math]::Round($script:val * 1.79)
  Px $g $cYellow ($cx - 2) 78 5 1; Px $g $cYellow ($cx - 1) 79 3 1; Px $g $cYellow $cx 80 1 1

  # save slots
  for ($i = 0; $i -lt 3; $i++) {
    $r = $rects["slot$i"]; $has = $presets[$i] -ne $null
    Box $g $r $(if ($script:hover -eq "slot$i" -and $has) { $cYellow } elseif ($has) { $cWhite } else { $cDim }) $cBlack
    $label = if ($has) { "$($i+1)P $($presets[$i])%" } else { "$($i+1)P ---" }
    Txt $g $label ($r[0] + 30) ($r[1] + 2) $(if ($has) { $cWhite } else { $cDim }) -Center
    $r = $rects["save$i"]; $hot = $script:hover -eq "save$i"
    $toast = $script:toastSlot -eq $i -and [datetime]::Now -lt $script:toastUntil
    Box $g $r $(if ($toast -or $hot) { $cYellow } else { $cDim }) $(if ($toast -or $hot) { $cHot } else { $cBlack })
    Txt $g $(if ($toast) { L '저장됨!' 'SAVED!' } else { L '저장' 'SAVE' }) ($r[0] + 30) ($r[1] + 1) $(if ($toast -or $hot) { $cYellow } else { $cWhite }) -Center
  }

  # buttons
  foreach ($k in 'apply', 'cancel') {
    $r = $rects[$k]; $hot = $script:hover -eq $k
    Box $g $r $(if ($hot) { $cYellow } else { $cWhite }) $cBlack
    Txt $g $(if ($k -eq 'apply') { L '적용' 'APPLY' } else { L '취소' 'CANCEL' }) ($r[0] + 31) ($r[1] + 2) $(if ($hot) { $cYellow } else { $cWhite }) -Center
    if ($hot -and $script:blink) { Arrow $g ($r[0] + 5) ($r[1] + 4) $cYellow }
  }
  $g.Dispose()
  $form.Invalidate()
}

# ---------- form ----------
$form = New-Object Windows.Forms.Form
$form.Text = 'Monitor Brightness'; $form.FormBorderStyle = 'None'; $form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size ($W * $Scale), ($H * $Scale); $form.TopMost = $true; $form.KeyPreview = $true
$form.BackColor = $cBg; $form.Icon = New-Object Drawing.Icon (Icon-Path $script:val)
[Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($form, $true, $null)
$form.Add_Paint({ param($sender, $e) $e.Graphics.InterpolationMode = 'NearestNeighbor'; $e.Graphics.PixelOffsetMode = 'Half'; $e.Graphics.DrawImage($canvas, 0, 0, $W * $Scale, $H * $Scale) })

# Live brightness: throttled (not debounced) so it keeps changing while dragging
$live = New-Object Windows.Forms.Timer; $live.Interval = 40
$live.Add_Tick({ if ($script:pending) { $script:pending = $false; Set-Bright $script:val } })
$live.Start()
$anim = New-Object Windows.Forms.Timer; $anim.Interval = 300
$anim.Add_Tick({ $script:blink = -not $script:blink; Render })
$anim.Start()

function Set-Val([int]$v, [switch]$Quiet) {
  $v = [math]::Max(0, [math]::Min(100, $v)); if ($v -eq $script:val) { return }
  $oldLv = [math]::Round($script:val / 10); $script:val = $v; $script:pending = $true
  if (-not $Quiet -and $beepWatch.ElapsedMilliseconds -gt 45) { Snd $sndMove; $beepWatch.Restart() }
  if ([math]::Round($v / 10) -ne $oldLv) { $form.Icon = New-Object Drawing.Icon (Icon-Path $v) }
  # While dragging, push brightness straight away instead of waiting for the timer
  if ($script:drag) { $script:pending = $false; Set-Bright $v }
  Render
  $form.Update()
}
function Hit($x, $y) { foreach ($k in $rects.Keys) { $r = $rects[$k]; if ($x -ge $r[0] -and $x -lt $r[0] + $r[2] -and $y -ge $r[1] -and $y -lt $r[1] + $r[3]) { return $k } }; '' }
function Bar-Val($x) { [int][math]::Round(($x - 30) / 1.79) }
function Do-Sound { $script:sound = -not $script:sound; Set-Content $soundFile $(if ($script:sound) { "on" } else { "off" }); Snd $sndLoad; Render }
function Do-Lang { $script:lang = L 'en' 'ko'; Set-Content $langFile $script:lang; Update-JumpList; Snd $sndLoad; Render }
function Do-Apply { $live.Stop(); Set-Bright $script:val; $script:applied = $script:val; Update-Icon $script:val; Snd $sndOk -Sync; $form.Close() }
function Do-Cancel { Snd $sndCancel -Sync; $form.Close() }
function Do-Load($i) { if ($presets[$i] -ne $null) { Snd $sndLoad; Set-Val $presets[$i] -Quiet } }
function Do-Save($i) { $presets[$i] = $script:val; ConvertTo-Json @($presets) | Set-Content $presetFile; Update-JumpList; Snd $sndSave; $script:toastSlot = $i; $script:toastUntil = [datetime]::Now.AddMilliseconds(900); Render }

$form.Add_MouseDown({ param($sender, $e)
  $x = [math]::Floor($e.X / $Scale); $y = [math]::Floor($e.Y / $Scale); $k = Hit $x $y
  switch -Regex ($k) {
    '^bar$'     { $script:drag = $true; Set-Val (Bar-Val $x) }
    '^slot(\d)' { Do-Load ([int]$matches[1]) }
    '^save(\d)' { Do-Save ([int]$matches[1]) }
    '^apply$'   { Do-Apply }
    '^cancel$'  { Do-Cancel }
    '^close$'   { Do-Cancel }
    '^sound$'   { Do-Sound }
    '^lang$'    { Do-Lang }
    '^$'        { if ($y -lt 22) { [G]::ReleaseCapture() | Out-Null; [G]::SendMessage($form.Handle, 0xA1, [IntPtr]2, [IntPtr]::Zero) | Out-Null } }
  } })
$form.Add_MouseMove({ param($sender, $e)
  $x = [math]::Floor($e.X / $Scale); $y = [math]::Floor($e.Y / $Scale)
  if ($script:drag) { Set-Val (Bar-Val $x); return }
  $k = Hit $x $y; if ($k -ne $script:hover) { $script:hover = $k; $form.Cursor = if ($k) { 'Hand' } else { 'Default' }; Render } })
$form.Add_MouseUp({ $script:drag = $false; Render })
$form.Add_MouseWheel({ param($sender, $e) Set-Val ($script:val + [math]::Sign($e.Delta) * 5) })
$form.Add_KeyDown({ param($sender, $e)
  switch ($e.KeyCode) {
    'Left'   { Set-Val ($script:val - 1) }
    'Right'  { Set-Val ($script:val + 1) }
    'Down'   { Set-Val ($script:val - 10) }
    'Up'     { Set-Val ($script:val + 10) }
    'Enter'  { Do-Apply }
    'Escape' { Do-Cancel }
    'D1' { Do-Load 0 }
    'D2' { Do-Load 1 }
    'D3' { Do-Load 2 }
    'M'  { Do-Sound }
    'L'  { Do-Lang }
  } })
# Closing without 적용 restores the brightness from before the window opened
$form.Add_FormClosing({ $live.Stop(); $anim.Stop(); if ($script:val -ne $script:applied) { Set-Bright $script:applied } })

Update-JumpList
# Brightness may have changed outside this tool (keyboard keys, Windows settings); bring every icon in line on open
if ((Get-Content (Join-Path $dir 'state.txt') -ErrorAction SilentlyContinue) -ne "$script:val") { Update-Icon $script:val }
Render
if ($env:BT_SNAPSHOT) { $canvas.Save($env:BT_SNAPSHOT); return }
[void]$form.ShowDialog()
