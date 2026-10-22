#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Model,
    [string]$Gpu = '0',
    [ValidateRange(256,2147483647)][int]$Context = 32768,
    [ValidateRange(128,2147483647)][int]$Budget = 16384,
    [ValidateRange(64,2147483647)][int]$Reserve = 16384,
    [ValidateRange(128,2147483647)][int]$Prefill = 256,
    [ValidateRange(1,2147483647)][int]$MaxTokens = 2048,
    [ValidateRange(1,1048576)][int]$HostMiB = 4096,
    [ValidateRange(0,2147483647)][int]$ThinkingBudget = 128,
    [ValidateRange(0,2147483647)][int]$SinkTokens = 12288,
    [ValidateRange(64,2147483647)][int]$RecentTokens = 1024,
    [ValidateRange(1,65535)][int]$Port = 18210,
    [ValidateSet('resident','cpu')][string]$VisionResidency = 'cpu',
    [ValidateRange(1,16384)][int]$VisionTokens = 1024,
    [ValidateSet('int8','bf16','fp8','nvfp4','k8v4','rk8v4','rk4v4','rk4v4-e8','rk2v4-e8')][string]$KvType = 'int8',
    [ValidateRange(0,15)][int]$MtpDrafts = 0,
    [switch]$DryRun,
    [switch]$NoVision
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$launcher = Join-Path $root 'scripts\windows\start-ninfer.ps1'
if (!(Test-Path -LiteralPath $launcher -PathType Leaf)) { throw "NInfer launcher missing: $launcher" }
if (!(Test-Path -LiteralPath $Model -PathType Leaf) -or [IO.Path]::GetExtension($Model) -ne '.ninfer') {
    throw 'Select an existing .ninfer artifact. GGUF files must be converted separately.'
}
if ($Budget % 64 -or $Reserve % 64 -or $Prefill % 128 -or $Prefill -gt $Reserve -or ([long]$Budget + $Reserve) -gt $Context) {
    throw 'v0.18 requires Budget/Reserve aligned to 64, Prefill aligned to 128 and <= Reserve, and Budget + Reserve <= Context.'
}
if ($Gpu -notmatch '^\d+$') { throw 'GPU must be a non-negative CUDA device index.' }
if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
    throw "Port $Port is already in use."
}

$parameters = @{
    Model = [IO.Path]::GetFullPath($Model)
    Gpu = $Gpu
    Context = $Context
    Budget = $Budget
    Reserve = $Reserve
    Prefill = $Prefill
    MaxTokens = $MaxTokens
    HostMiB = $HostMiB
    ThinkingBudget = $ThinkingBudget
    SinkTokens = $SinkTokens
    RecentTokens = $RecentTokens
    Port = $Port
    KvType = $KvType
    MtpDrafts = $MtpDrafts
    NgramDrafts = 0
    VisionResidency = $VisionResidency
    VisionTokens = $VisionTokens
}
if ($MtpDrafts -gt 0) {
    $parameters.AdaptiveMtp = $true
}
if ($NoVision) { $parameters.NoVision = $true }
if ($DryRun) { $parameters.DryRun = $true }

& $launcher @parameters
