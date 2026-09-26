# Creates the pixel icons and a "Monitor Brightness" shortcut on the desktop, then offers to pin it to the taskbar
Add-Type -AssemblyName System.Windows.Forms
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ko = (Get-Culture).TwoLetterISOLanguageName -eq 'ko'
function L($k, $e) { if ($ko) { $k } else { $e } }

Get-ChildItem $dir -Recurse | Unblock-File
& (Join-Path $dir 'make_icons.ps1') | Out-Null
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Monitor Brightness.lnk'
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$sc.TargetPath = "$env:WINDIR\System32\wscript.exe"
$sc.Arguments = '"' + (Join-Path $dir 'launch.vbs') + '"'
$sc.WorkingDirectory = $dir
# Start with the bulb that matches the current brightness, so a pin made right now looks right too
$now = (Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue | Select-Object -First 1).CurrentBrightness
if ($now -eq $null) { $now = 100 }
$sc.IconLocation = (Join-Path $dir ('bulb_{0}.ico' -f ([math]::Round($now / 10) * 10))) + ',0'
$sc.Description = 'Monitor Brightness - laptop + external monitors'
$sc.Save()
& (Join-Path $dir 'set_appid.ps1') | Out-Null
Write-Host (L '설치 완료! 바탕화면의 "Monitor Brightness" 아이콘을 더블클릭하세요.' 'Installed! Double-click "Monitor Brightness" on your desktop.') -ForegroundColor Green

# ---- offer to pin to the taskbar ----
$ask = [Windows.Forms.MessageBox]::Show((L '작업 표시줄에 고정할까요?' 'Pin Monitor Brightness to the taskbar?'), 'Monitor Brightness', 'YesNo', 'Question')
if ($ask -eq 'Yes') {
  $pinDir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
  $isPinned = { @(Get-ChildItem $pinDir -Filter *.lnk -ErrorAction SilentlyContinue | Where-Object {
      (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName).Arguments -like "*$(Join-Path $dir 'launch.vbs')*" }).Count -gt 0 }

  # Older Windows builds still honor the shell "Pin to taskbar" verb; Windows 11 blocks programs from pinning themselves
  $item = (New-Object -ComObject Shell.Application).Namespace((Split-Path $lnk)).ParseName((Split-Path $lnk -Leaf))
  $verb = $item.Verbs() | Where-Object { $_.Name.Replace('&', '') -match '작업 표시줄에 고정|Pin to taskbar' } | Select-Object -First 1
  if ($verb) { $verb.DoIt(); Start-Sleep -Milliseconds 800 }

  if (& $isPinned) {
    Write-Host (L '작업 표시줄에 고정했어요.' 'Pinned to the taskbar.') -ForegroundColor Green
  } else {
    # Show the icon selected in Explorer so it's one right-click away
    Start-Process explorer.exe "/select,`"$lnk`""
    [void][Windows.Forms.MessageBox]::Show((L "Windows 11은 프로그램이 스스로 작업 표시줄에 고정하는 것을 막고 있어요.`n`n방금 선택된 'Monitor Brightness' 아이콘을 우클릭한 뒤`n'작업 표시줄에 고정'을 눌러 주세요.`n(메뉴에 없으면 '추가 옵션 표시'를 먼저 누르세요)" "Windows 11 doesn't let programs pin themselves.`n`nRight-click the selected 'Monitor Brightness' icon`nand choose 'Pin to taskbar'.`n(If you don't see it, click 'Show more options' first.)"), 'Monitor Brightness', 'OK', 'Information')
  }
}
Write-Host (L '작업 표시줄 우클릭 메뉴는 창을 한 번 열었다 닫으면 생겨요.' 'Open and close the window once to enable the taskbar right-click presets.')
