# Restores full brightness and removes the shortcut, pinned icon and right-click menu entries
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $dir 'ui.ps1') -Apply 100
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) '밝기 전환.lnk') -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\밝기 전환.lnk') -ErrorAction SilentlyContinue
1..3 | ForEach-Object { Remove-Item "HKCU:\Software\Classes\lnkfile\shell\BrightnessPreset$_" -Recurse -ErrorAction SilentlyContinue }
Write-Host '제거 완료. 이제 이 폴더를 지워도 됩니다.' -ForegroundColor Green
