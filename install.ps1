# Creates the pixel icons and a "밝기 전환" shortcut on the desktop
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Get-ChildItem $dir -Recurse | Unblock-File
& (Join-Path $dir 'make_icons.ps1') | Out-Null
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) '밝기 전환.lnk'
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$sc.TargetPath = "$env:WINDIR\System32\wscript.exe"
$sc.Arguments = '"' + (Join-Path $dir 'launch.vbs') + '"'
$sc.WorkingDirectory = $dir
$sc.IconLocation = (Join-Path $dir 'bulb_100.ico') + ',0'
$sc.Description = '화면 밝기 조절'
$sc.Save()
& (Join-Path $dir 'set_appid.ps1') | Out-Null
Write-Host '설치 완료! 바탕화면의 "밝기 전환" 아이콘을 더블클릭하세요.' -ForegroundColor Green
Write-Host '작업표시줄 우클릭 메뉴는 창을 한 번 열었다 닫으면 생깁니다.'
