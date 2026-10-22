#Requires -Version 7.0
[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port = 18210)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$server = [IO.Path]::GetFullPath((Join-Path $root 'workers\ninfer\ninfer-kvmem-server.exe'))
$processes = @(Get-CimInstance Win32_Process -Filter "Name='ninfer-kvmem-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
        [string]::Equals($_.ExecutablePath, $server, [StringComparison]::OrdinalIgnoreCase) -and
        $_.CommandLine -match ('"?--port"?\s+"?' + $Port + '"?(?:\s|$)')
    })
foreach ($process in $processes) {
    Stop-Process -Id $process.ProcessId -ErrorAction Stop
    Wait-Process -Id $process.ProcessId -Timeout 20 -ErrorAction SilentlyContinue
    if (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue) {
        throw "NInfer server PID $($process.ProcessId) did not exit."
    }
}
if (!$processes.Count) { Write-Output "No KVMem v0.18 server is listening on port $Port." }
else { Write-Output "Stopped KVMem v0.18 server on port $Port." }
