Option Explicit
Dim shell, fso, basePath, scriptPath, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
basePath = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(basePath, "windows\VargaRemote-Setup.ps1")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File """ & scriptPath & """"
shell.Run command, 0, False

