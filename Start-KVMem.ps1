#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Model = '',
    [string]$Mmproj = '',
    [string]$ModelAlias = 'kvmem-current',
    [string]$Gpu = 'auto',
    [int]$Port = 18200,
    [int]$Context = 32768,
    [int]$GpuLayers = 99,
    [int]$KvmemBudget = 8192,
    [int]$GenerationReserve = 2048,
    [int]$CpuMemoryGiB = 1,
    [int]$BatchSize = 256,
    [int]$UBatchSize = 128,
    [int]$Threads = 0,
    [int]$ThreadsBatch = 0,
    [ValidateSet('f16','f32','q8_0','q5_0','q4_0')][string]$KvDtype = 'q5_0',
    [ValidateSet('on','off','auto')][string]$FlashAttention = 'on',
    [ValidateSet('auto','none','mmap','mlock','mmap+mlock','dio')][string]$LoadMode = 'auto',
    [int]$MaxTokens = 2048,
    [double]$Temperature = 0.7,
    [double]$TopP = 0.8,
    [int]$TopK = 20,
    [double]$MinP = 0,
    [double]$RepeatPenalty = 1.0,
    [double]$PresencePenalty = 0,
    [double]$FrequencyPenalty = 0,
    [long]$Seed = -1,
    [bool]$DisableThinking = $true
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$localizationModule = Join-Path $root 'KVMem-Localization.psm1'
if (!(Test-Path -LiteralPath $localizationModule -PathType Leaf)) { throw 'KVMem language resources are missing; re-extract the complete package.' }
Import-Module $localizationModule -Force
$languageFile = Join-Path $root 'codex\ui-language.json'
if (Test-Path -LiteralPath $languageFile -PathType Leaf) {
    try { $savedLanguage=(Get-Content -LiteralPath $languageFile -Raw|ConvertFrom-Json).Language; if($savedLanguage -in @('zh','en')){Set-KVMemUiLanguage -Language $savedLanguage} } catch {}
}
$compatibilityModule = Join-Path $root 'KVMem-Compatibility.psm1'
if (!(Test-Path -LiteralPath $compatibilityModule -PathType Leaf)) { throw 'KVMem GPU compatibility checker is missing; re-extract the complete package.' }
Import-Module $compatibilityModule -Force
$runtime = Join-Path $root 'runtime'
$server = Join-Path $runtime 'bin\llama-kvmem-server.exe'
$ui = Join-Path $runtime 'share\kvmem\ui'
$logs = Join-Path $root 'codex\logs'
$pidFile = Join-Path $root 'codex\server.pid'
if (!(Test-Path -LiteralPath $server)) { throw "KVMem server not found: $server" }
if ($Gpu -eq 'auto') {
    $compatibility = Get-KVMemBackendCompatibility -ServerPath $server
    if (!$compatibility.Supported) { throw $(if((Get-KVMemUiLanguage) -eq 'en'){$compatibility.MessageEnglish}else{$compatibility.Message}) }
    $Gpu = [string]$compatibility.RecommendedGpuIndex
} else {
    $compatibility = Get-KVMemBackendCompatibility -ServerPath $server
    if (!$compatibility.Supported) { throw $(if((Get-KVMemUiLanguage) -eq 'en'){$compatibility.MessageEnglish}else{$compatibility.Message}) }
    if ($Gpu -notmatch '^\d+$') { throw "GPU must be 'auto' or a CUDA device index. Detected usable devices: $(($compatibility.Devices | Where-Object Supported | ForEach-Object { "$($_.Index): $($_.Name) ($($_.Target))" }) -join ', ')" }
    $selectedDevice = $compatibility.Devices | Where-Object Index -eq ([int]$Gpu) | Select-Object -First 1
    if (!$selectedDevice -or !$selectedDevice.Supported) {
        if((Get-KVMemUiLanguage) -eq 'en'){throw "CUDA device index $Gpu has no compatible target in this KVMem build. Supported targets: $($compatibility.Targets -join ', ')."}
        throw "CUDA 设备编号 $Gpu 在当前 KVMem 版本中没有兼容的计算目标。支持目标：$($compatibility.Targets -join ', ')。"
    }
}
if ([string]::IsNullOrWhiteSpace($Model)) { throw 'Select a local GGUF model with -Model.' }
if (!(Test-Path -LiteralPath $Model)) { throw "GGUF model not found: $Model" }
if ($Mmproj -and !(Test-Path -LiteralPath $Mmproj)) { throw "mmproj not found: $Mmproj" }
$listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
if ($listener) { throw "Port $Port is already in use by PID $($listener[0].OwningProcess). Stop that service or select another port." }
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $logs "server-$stamp.stdout.log"
$stderr = Join-Path $logs "server-$stamp.stderr.log"
function Quote-Arg([string]$Value) { '"' + $Value.Replace('"','\"') + '"' }
$argList = @(
    '-m', (Quote-Arg $Model),
    '--host', '127.0.0.1', '--port', "$Port", '--alias', (Quote-Arg $ModelAlias),
    '-c', "$Context", '-n', "$MaxTokens", '-ngl', "$GpuLayers",
    '-b', "$BatchSize", '-ub', "$UBatchSize", '-t', "$Threads", '-fa', $FlashAttention,
    '--load-mode', $LoadMode,
    '--kvmem', '--kvmem-budget', "$KvmemBudget", '--kvmem-gen-reserve', "$GenerationReserve",
    '--kvmem-block-tokens', '128', '--kvmem-sink-tokens', '1024', '--kvmem-recent-tokens', '2048',
    '--kvmem-query-policy', 'user', '--kvmem-gpu-ratio', '0.20', '--kvmem-cpu-gb', "$CpuMemoryGiB",
    '--kv-dtype', $KvDtype,
    '--temp', $Temperature.ToString([Globalization.CultureInfo]::InvariantCulture),
    '--top-p', $TopP.ToString([Globalization.CultureInfo]::InvariantCulture), '--top-k', "$TopK",
    '--min-p', $MinP.ToString([Globalization.CultureInfo]::InvariantCulture),
    '--repeat-penalty', $RepeatPenalty.ToString([Globalization.CultureInfo]::InvariantCulture),
    '--presence-penalty', $PresencePenalty.ToString([Globalization.CultureInfo]::InvariantCulture),
    '--frequency-penalty', $FrequencyPenalty.ToString([Globalization.CultureInfo]::InvariantCulture),
    '--ui-dir', (Quote-Arg $ui), '--webui', '--verbosity', '3'
)
if ($ThreadsBatch -gt 0) { $argList += @('-tb', "$ThreadsBatch") }
if ($Seed -ge 0) { $argList += @('--seed', "$Seed") }
if ($DisableThinking) { $argList += @('--no-think', '--reasoning-effort', 'none') }
if ($Mmproj) {
    $argList += @('--mmproj', (Quote-Arg $Mmproj), '--no-mmproj-offload', '--image-max-tokens', '512')
}
$env:CUDA_VISIBLE_DEVICES = $Gpu
$env:CUDA_DEVICE_ORDER = 'PCI_BUS_ID'
$proc = Start-Process -FilePath $server -WorkingDirectory $runtime -ArgumentList ($argList -join ' ') -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
Set-Content -LiteralPath $pidFile -Value $proc.Id -Encoding ascii
[pscustomobject]@{ PID=$proc.Id; Model=$Model; Mmproj=if($Mmproj){$Mmproj}else{'(text only)'}; Context=$Context; GpuLayers=$GpuLayers; Batch=$BatchSize;UBatch=$UBatchSize;Threads=$Threads;KvmemBudget=$KvmemBudget;KV=$KvDtype;FlashAttention=$FlashAttention;MaxTokens=$MaxTokens;Port=$Port;Stdout=$stdout;Stderr=$stderr } | Format-List
