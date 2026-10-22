#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Model,
    [string]$Worker,
    [string]$Gpu = $(if ($env:CUDA_VISIBLE_DEVICES) { $env:CUDA_VISIBLE_DEVICES } else { '0' }),
    [uint32[]]$StageLayers = @(),
    [ValidateRange(1, 65535)][int]$Port = 18200,
    [string]$ListenHost = '127.0.0.1',
    [ValidateRange(256, 2147483647)][int]$Context = 204800,
    [ValidateRange(128, 2147483647)][int]$Budget = 36864,
    [ValidateRange(64, 2147483647)][int]$Reserve = 16384,
    [ValidateRange(1, 1048576)][int]$HostMiB = 12288,
    [ValidateRange(128, 2147483647)][int]$Prefill = 256,
    [ValidateRange(1, 2147483647)][int]$MaxTokens = 16384,
    [string]$KvType = 'int8',
    [ValidateRange(0, 15)][int]$MtpDrafts = 4,
    [switch]$AdaptiveMtp = $true,
    [switch]$FastPrefill,
    [ValidateRange(0, 63)][int]$NgramDrafts = 31,
    [ValidateRange(4, 64)][int]$NgramMinMatch = 12,
    [ValidateRange(1, 8)][int]$Concurrency = 1,
    [ValidateRange(1, 16)][int]$RetainedSessions = 1,
    [switch]$Vision = $true,
    [switch]$NoVision,
    [ValidateSet('resident', 'cpu')][string]$VisionResidency = 'cpu',
    [ValidateRange(1, 16384)][int]$VisionTokens = 1024,
    [ValidateSet('off', 'auto')][string]$DeviceProfile = 'off',
    [ValidateRange(0, 2147483647)][int]$ThinkingBudget = 8192,
    [ValidateRange(0, 2147483647)][int]$SinkTokens = 12288,
    [ValidateRange(0, 2147483647)][int]$RecentTokens = 1024,
    [switch]$NoLrfu,
    [ValidateRange(0.0, 1.0)][double]$LrfuLambda = 0.5,
    [ValidateScript({ $_ -gt 0 -and $_ -le 1 })][double]$LrfuTopFraction = 0.9,
    [ValidateSet('mean', 'max')][string]$ScoreAggregation = 'max',
    [string]$DiskPath,
    [ValidateRange(1, 1048576)][int]$DiskMiB = 4096,
    [string[]]$WorkerArgs = @(),
    [switch]$Describe,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$forward = @{}
foreach ($entry in $PSBoundParameters.GetEnumerator()) { $forward[$entry.Key] = $entry.Value }
$forward['Backend'] = 'ninfer'
foreach ($parameterName in @('Gpu', 'Context', 'Budget', 'Reserve', 'HostMiB', 'Prefill', 'MaxTokens', 'KvType', 'MtpDrafts', 'AdaptiveMtp', 'NgramDrafts', 'NgramMinMatch', 'Concurrency', 'RetainedSessions', 'Vision', 'VisionResidency', 'VisionTokens', 'DeviceProfile', 'ThinkingBudget', 'SinkTokens', 'RecentTokens', 'LrfuLambda', 'LrfuTopFraction', 'ScoreAggregation')) {
    if (!$forward.ContainsKey($parameterName)) { $forward[$parameterName] = Get-Variable -Name $parameterName -ValueOnly }
}
$null = $forward.Remove('NoVision')
$forward['Vision'] = [bool]$Vision -and !$NoVision
$forward['VisionResidency'] = if ($forward['Vision']) { $VisionResidency } else { 'resident' }
if (!$MtpDrafts) {
    if (!$PSBoundParameters.ContainsKey('AdaptiveMtp')) { $forward['AdaptiveMtp'] = $false }
    if (!$PSBoundParameters.ContainsKey('NgramDrafts')) { $forward['NgramDrafts'] = 0 }
}
if (!$forward.ContainsKey('Model')) { $forward['Model'] = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../model.ninfer')) }
& (Join-Path $PSScriptRoot 'start-backend.ps1') @forward
