#Requires -Version 7.0
<#
    构建便携包：把源代码与 payloads 里的两个上游压缩包打成一个可分发的 ZIP。

    payloads 目录需要包含（文件名必须完全一致，Bootstrap-Portable.ps1 会按名字查找）：
      kvmem-v0.16.0-rc3-windows-x86_64-cuda13.2.86.zip
      PowerShell-7.6.7-win-x64.zip

    用法：
      pwsh -File .\Build-Portable.ps1
      pwsh -File .\Build-Portable.ps1 -OutputDir D:\dist
#>
[CmdletBinding()]
param(
    [string]$OutputDir = (Join-Path $PSScriptRoot 'dist'),
    [string]$Version
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot

if (!$Version) {
    $manifestPath = Join-Path $root 'package-manifest.json'
    if (!(Test-Path -LiteralPath $manifestPath)) { throw 'package-manifest.json not found.' }
    $Version = (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).Version
}
if (!$Version) { throw 'Version could not be determined.' }

$packageName = "KVMem-Windows-Controller-Portable-v$Version"
$staging = Join-Path ([IO.Path]::GetTempPath()) "kvmem-build-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
$stageRoot = Join-Path $staging $packageName

# Files that go into the package. Keep this list explicit: logs, task records and
# local models must never leak into a release.
$files = @(
    'Bootstrap-Portable.ps1'
    'Build-Portable.ps1'
    'KVMem-Compatibility.psm1'
    'KVMem-Controller.ps1'
    'KVMem-Localization.psm1'
    'LICENSE'
    'Open-KVMem-Controller.bat'
    'Open-KVMem-Controller.vbs'
    'package-manifest.json'
    'README.md'
    'Start-KVMem.ps1'
    'Stop-KVMem.ps1'
    'THIRD-PARTY-NOTICES.md'
    '.gitignore'
    '.gitattributes'
    'assets\kvmem.ico'
    'docs\ui-preview.png'
)

$payloads = @(
    'kvmem-v0.16.0-rc3-windows-x86_64-cuda13.2.86.zip'
    'PowerShell-7.6.7-win-x64.zip'
)

Write-Host "Building $packageName"

$missing = @()
foreach ($rel in $files) {
    if (!(Test-Path -LiteralPath (Join-Path $root $rel) -PathType Leaf)) { $missing += $rel }
}
foreach ($name in $payloads) {
    if (!(Test-Path -LiteralPath (Join-Path $root "payloads\$name") -PathType Leaf)) { $missing += "payloads\$name" }
}
if ($missing.Count -gt 0) {
    throw "Missing required file(s):`n  $($missing -join "`n  ")`n`nPlace the upstream archives in .\payloads\ and retry."
}

New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
foreach ($rel in $files) {
    $dest = Join-Path $stageRoot $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $rel) -Destination $dest -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'payloads') | Out-Null
foreach ($name in $payloads) {
    Write-Host "  staging payload: $name"
    Copy-Item -LiteralPath (Join-Path $root "payloads\$name") -Destination (Join-Path $stageRoot "payloads\$name") -Force
}
# The launcher creates models/ on first run; ship it so the folder exists after extraction.
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'models') | Out-Null
Set-Content -LiteralPath (Join-Path $stageRoot 'models\.gitkeep') -Value '' -NoNewline

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$zipPath = Join-Path $OutputDir "$packageName.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

Write-Host 'Compressing...'
$zipStream = [IO.File]::Open($zipPath, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $archive = [IO.Compression.ZipArchive]::new($zipStream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        $filesOnDisk = Get-ChildItem -LiteralPath $stageRoot -Recurse -File -Force
        $index = 0
        foreach ($file in $filesOnDisk) {
            $index++
            $entryName = "$packageName/" + [IO.Path]::GetRelativePath($stageRoot, $file.FullName).Replace('\', '/')
            # Payload archives are already compressed; store them to keep the build fast.
            $level = if ($file.Extension -eq '.zip') {
                [IO.Compression.CompressionLevel]::NoCompression
            } else {
                [IO.Compression.CompressionLevel]::Optimal
            }
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entryName, $level)
            Write-Progress -Activity 'Packing' -Status $file.Name -PercentComplete (($index / $filesOnDisk.Count) * 100)
        }
    }
    finally { $archive.Dispose() }
}
finally { $zipStream.Dispose() }
Write-Progress -Activity 'Packing' -Completed

# --- Verify -----------------------------------------------------------------
$verifyErrors = @()
$z = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $names = $z.Entries | ForEach-Object { $_.FullName }
    foreach ($rel in $files) {
        $needle = "$packageName/" + $rel.Replace('\', '/')
        if ($names -notcontains $needle) { $verifyErrors += "missing entry: $needle" }
    }
    foreach ($name in $payloads) {
        $needle = "$packageName/payloads/$name"
        if ($names -notcontains $needle) { $verifyErrors += "missing entry: $needle" }
    }
    $leak = $names | Where-Object { $_ -match '/codex/|\.log$|\.gguf$|/runtime/' }
    if ($leak) { $verifyErrors += "unexpected entries: $($leak -join ', ')" }
}
finally { $z.Dispose() }

$zipSize = (Get-Item -LiteralPath $zipPath).Length
$sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash

Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue

if ($verifyErrors.Count -gt 0) {
    $verifyErrors | ForEach-Object { Write-Error $_ }
    throw 'Package verification failed.'
}

Write-Host ''
Write-Host "Package : $zipPath"
Write-Host "Size    : $([math]::Round($zipSize / 1MB, 1)) MB"
Write-Host "SHA-256 : $sha"
Write-Host 'Verification passed (all required entries present, no logs/models/runtime leaked).'
