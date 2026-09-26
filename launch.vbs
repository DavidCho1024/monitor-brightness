d = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
a = ""
If WScript.Arguments.Count > 0 Then a = " -Apply " & WScript.Arguments(0)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & d & "\ui.ps1""" & a, 0, False
