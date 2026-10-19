#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$pidFile = Join-Path $root 'codex\server.pid'
$serverPath = (Resolve-Path (Join-Path $root 'runtime\bin\llama-kvmem-server.exe')).Path
if (!(Test-Path -LiteralPath $pidFile)) { Write-Output 'No KVMem PID record is present.'; exit 0 }
$serverPid = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
$p = Get-CimInstance Win32_Process -Filter "ProcessId = $serverPid" -ErrorAction SilentlyContinue
if (!$p) { Remove-Item -LiteralPath $pidFile -Force; Write-Output 'Recorded KVMem process is already stopped.'; exit 0 }
if ([string]::Equals($p.ExecutablePath,$serverPath,[StringComparison]::OrdinalIgnoreCase)) {
    Stop-Process -Id $serverPid
    Wait-Process -Id $serverPid -Timeout 20 -ErrorAction SilentlyContinue
    if (Get-Process -Id $serverPid -ErrorAction SilentlyContinue) { throw "KVMem PID $serverPid did not exit." }
    Remove-Item -LiteralPath $pidFile -Force
    Write-Output "Stopped KVMem PID $serverPid."
} else { throw "PID $serverPid belongs to another executable; left it running." }
