Set-StrictMode -Version Latest

$script:KVMemBackendInfo = [pscustomobject]@{
    Name = 'KVMem llama.cpp / GGUF'
    Release = 'v0.16.0-rc3'
    WindowsPackage = 'CUDA 13.2.86'
    ReleaseUrl = 'https://github.com/kvmem/kvmem/releases/tag/v0.16.0-rc3'
    Targets = @{
        '7.5'  = 'sm_75'
        '8.0'  = 'sm_80'
        '8.6'  = 'sm_86'
        '8.9'  = 'sm_89'
        '9.0'  = 'sm_90'
        '12.0' = 'sm_120a'
    }
    TestedCapability = '12.0 (RTX 5060 Ti; upstream inference test)'
}

function Get-KVMemBackendCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServerPath,
        # Test seam: supply captured output to test the compatibility matrix without a GPU.
        [string]$DeviceListOutput,
        [int]$NativeExitCode = 0
    )

    $output = $DeviceListOutput
    if ($PSBoundParameters.ContainsKey('DeviceListOutput')) {
        $nativeCode = $NativeExitCode
    } else {
        if (!(Test-Path -LiteralPath $ServerPath -PathType Leaf)) {
            return [pscustomobject]@{
                Supported = $false; Devices = @(); RecommendedGpuIndex = $null
                Message = "未找到 KVMem 服务端：$ServerPath`r`n请重新解压完整的便携包。"
                MessageEnglish = "KVMem server not found: $ServerPath`r`nRe-extract the complete portable package."
            }
        }
        $lines = @(& $ServerPath --list-devices 2>&1)
        $nativeCode = $LASTEXITCODE
        $output = ($lines | ForEach-Object { [string]$_ }) -join "`n"
    }

    $devices = @()
    foreach ($line in ($output -split "`r?`n")) {
        if ($line -match 'Device\s+(?<index>\d+):\s+(?<name>.+?),\s+compute capability\s+(?<cap>\d+\.\d+)') {
            $cap = $Matches.cap
            $target = $script:KVMemBackendInfo.Targets[$cap]
            $devices += [pscustomobject]@{
                Index = [int]$Matches.index
                Name = $Matches.name.Trim()
                ComputeCapability = $cap
                Target = if ($target) { $target } else { $null }
                Supported = [bool]$target
            }
        }
    }

    $cudaEnumerationSucceeded = ($nativeCode -eq 0 -and $devices.Count -gt 0)
    if (!$PSBoundParameters.ContainsKey('DeviceListOutput') -and !$cudaEnumerationSucceeded) {
        $smiCommand = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        $smiPath = if ($smiCommand) { $smiCommand.Source } else { $null }
        if (!$smiPath) {
            $standardSmi = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
            if (Test-Path -LiteralPath $standardSmi -PathType Leaf) { $smiPath = $standardSmi }
        }
        if ($smiPath) {
            $smiLines = @(& $smiPath --query-gpu=index,name,compute_cap --format=csv,noheader,nounits 2>$null)
            $smiExit = $LASTEXITCODE
            if ($smiExit -eq 0) {
                foreach ($line in $smiLines) {
                    if ([string]$line -match '^\s*(?<index>\d+),\s*(?<name>.+),\s*(?<cap>\d+\.\d+)\s*$') {
                        $cap = $Matches.cap
                        $target = $script:KVMemBackendInfo.Targets[$cap]
                        $devices += [pscustomobject]@{
                            Index = [int]$Matches.index; Name = $Matches.name.Trim()
                            ComputeCapability = $cap; Target = if ($target) { $target } else { $null }
                            Supported = [bool]$target
                        }
                    }
                }
            }
        }
    }

    $targets = @($script:KVMemBackendInfo.Targets.GetEnumerator() | Sort-Object Name | ForEach-Object Value)
    $supportedDevices = @($devices | Where-Object Supported)
    if (!$devices.Count) {
        $detail = ($output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 8) -join "`r`n"
        if (!$detail) { $detail = '没有检测到 NVIDIA CUDA 显卡。' }
        $message = "没有检测到可用的 NVIDIA CUDA 显卡，因此当前 GGUF/CUDA 后端无法通过兼容性检查。`r`n`r`n诊断信息：`r`n$detail"
        $messageEnglish = "No usable NVIDIA CUDA GPU was detected, so the current GGUF/CUDA backend cannot pass compatibility checks.`r`n`r`nDiagnostic details:`r`n$detail"
    } elseif (!$supportedDevices.Count) {
        $detected = ($devices | ForEach-Object { "$($_.Name) (sm_$($_.ComputeCapability.Replace('.','')))" }) -join ', '
        $message = "检测到 $detected，但当前捆绑的 KVMem llama.cpp/GGUF CUDA 13.2.86 包没有匹配的 GPU 编译目标。`r`n该包包含：$($targets -join ', ')。对 sm_61（RTX 10 系），截至 2026-10-19 核对的 KVMem 预编译发布包没有列出对应 GGUF/CUDA 目标。安装本控制器不会改变显卡驱动。请查看 KVMem 发布页是否已有新架构运行包：$($script:KVMemBackendInfo.ReleaseUrl)"
        $messageEnglish = "Detected $detected, but the bundled KVMem llama.cpp/GGUF CUDA 13.2.86 package has no matching GPU build target.`r`nIncluded targets: $($targets -join ', '). For sm_61 (RTX 10 series), the KVMem prebuilt release inventory checked on 2026-10-19 lists no matching GGUF/CUDA target. This controller will not change your GPU driver. Check whether KVMem has since published a runtime for this architecture: $($script:KVMemBackendInfo.ReleaseUrl)"
    } elseif (!$cudaEnumerationSucceeded) {
        $detail = ($output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 8) -join "`r`n"
        if (!$detail) { $detail = 'KVMem 未能初始化 CUDA 并枚举显卡。' }
        $message = "KVMem CUDA/驱动检查失败。当前包为 $($script:KVMemBackendInfo.Name) $($script:KVMemBackendInfo.Release) / $($script:KVMemBackendInfo.WindowsPackage)。`r`n请检查 NVIDIA 驱动是否能运行 CUDA 13.2，并安装 Microsoft Visual C++ x64 运行库。上游只记录了已测试驱动，没有公布可保证的最低版本。`r`n`r`n诊断信息：`r`n$detail"
        $messageEnglish = "KVMem could not initialize CUDA or enumerate the GPU. This package is $($script:KVMemBackendInfo.Name) $($script:KVMemBackendInfo.Release) / $($script:KVMemBackendInfo.WindowsPackage).`r`nCheck that the NVIDIA driver supports CUDA 13.2 and install the Microsoft Visual C++ x64 runtime. Upstream lists a tested driver but does not specify a guaranteed minimum version.`r`n`r`nDiagnostic details:`r`n$detail"
    } else {
        $devicesText = ($supportedDevices | ForEach-Object { "$($_.Name) (sm_$($_.ComputeCapability.Replace('.','')) → $($_.Target))" }) -join ', '
        $message = $null
        $messageEnglish = $null
    }

    [pscustomobject]@{
        Supported = $cudaEnumerationSucceeded -and ($supportedDevices.Count -gt 0)
        NativeExitCode = $nativeCode
        Devices = @($devices)
        RecommendedGpuIndex = if ($supportedDevices.Count) { $supportedDevices[0].Index } else { $null }
        Backend = "$($script:KVMemBackendInfo.Name) $($script:KVMemBackendInfo.Release)"
        Targets = $targets
        Summary = if ($supportedDevices.Count -and $nativeCode -eq 0) { "兼容：$devicesText；构建目标 $($targets -join ', ')" } else { $null }
        SummaryEnglish = if ($supportedDevices.Count -and $nativeCode -eq 0) { "Compatible: $devicesText; build targets $($targets -join ', ')" } else { $null }
        Message = $message
        MessageEnglish = $messageEnglish
    }
}

Export-ModuleMember -Function Get-KVMemBackendCompatibility
