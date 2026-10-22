Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)

pwsh = fso.BuildPath(shell.ExpandEnvironmentStrings("%ProgramFiles%"), "PowerShell\7\pwsh.exe")
If Not fso.FileExists(pwsh) Then
    MsgBox "PowerShell 7 was not found. Install PowerShell 7 to open the KVMem v0.18 panel.", 16, "KVMem v0.18"
    WScript.Quit 1
End If

script = Chr(34) & pwsh & Chr(34) & " -NoProfile -STA -ExecutionPolicy Bypass -File " & Chr(34) & fso.BuildPath(base, "KVMem-v018-ControlPanel.ps1") & Chr(34)
shell.CurrentDirectory = base
shell.Run script, 1, False
