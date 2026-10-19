Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)

pwsh = fso.BuildPath(base, ".tools\pwsh\pwsh.exe")
If Not fso.FileExists(pwsh) Then
    programFiles = shell.ExpandEnvironmentStrings("%ProgramFiles%")
    pwsh = fso.BuildPath(programFiles, "PowerShell\7\pwsh.exe")
End If
If Not fso.FileExists(pwsh) Then
    MsgBox "PowerShell 7 was not found. Install PowerShell 7 or use the portable release package.", 16, "KVMem Controller"
    WScript.Quit 1
End If

script = Chr(34) & pwsh & Chr(34) & " -NoProfile -STA -ExecutionPolicy Bypass -File " & Chr(34) & fso.BuildPath(base, "KVMem-Controller.ps1") & Chr(34)
shell.CurrentDirectory = base
shell.Run script, 1, False
