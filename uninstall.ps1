# Restores full brightness and removes every shortcut, pinned icon and right-click menu entry of this tool
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $dir 'ui.ps1') -Apply 100
$ws = New-Object -ComObject WScript.Shell
Get-ChildItem ([Environment]::GetFolderPath('Desktop')), (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar') -Filter *.lnk -ErrorAction SilentlyContinue |
  Where-Object { $ws.CreateShortcut($_.FullName).Arguments -like "*$(Join-Path $dir 'launch.vbs')*" } | Remove-Item -ErrorAction SilentlyContinue
1..3 | ForEach-Object { Remove-Item "HKCU:\Software\Classes\lnkfile\shell\BrightnessPreset$_" -Recurse -ErrorAction SilentlyContinue }
Write-Host '제거 완료. 이제 이 폴더를 지워도 됩니다. / Uninstalled. You can delete this folder now.' -ForegroundColor Green
