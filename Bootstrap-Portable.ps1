param([string]$Root = $PSScriptRoot)
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
$payload=Join-Path $Root 'payloads'
$runtimeArchive=Join-Path $payload 'kvmem-v0.16.0-rc3-windows-x86_64-cuda13.2.86.zip'
$powershellArchive=Join-Path $payload 'PowerShell-7.6.7-win-x64.zip'
$runtimeSha='76e450bd9f84a43f61a2c2a1c742dc8b98a43f39b12f7e79cfa2043e5e456bec'
$powershellSha='D2F952EBDBF24386CB8923553AA58E41A846DB35A6155EA04C58142A4B16DBB7'

function Expand-VerifiedArchive([string]$Archive,[string]$ExpectedSha,[string]$Destination,[string]$RequiredFile) {
    if(!(Test-Path -LiteralPath $Archive -PathType Leaf)) {
        throw "Portable payload is missing: $Archive`nDownload the portable ZIP from the Releases page, then extract all of its files together."
    }
    Write-Host "Checking SHA-256: $([IO.Path]::GetFileName($Archive))"
    $actual=(Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash
    if(![string]::Equals($actual,$ExpectedSha,[StringComparison]::OrdinalIgnoreCase)) {
        throw "SHA-256 verification failed for $([IO.Path]::GetFileName($Archive)); extraction was cancelled."
    }
    if(Test-Path -LiteralPath $Destination) {
        if(Test-Path -LiteralPath (Join-Path $Destination $RequiredFile) -PathType Leaf){return}
        throw "Incomplete destination already exists: $Destination`nMove it aside and retry; no files were overwritten."
    }
    New-Item -ItemType Directory -Force -Path $Destination|Out-Null
    Write-Host "Extracting $([IO.Path]::GetFileName($Archive)) ..."
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination
    # Upstream release ZIPs are wrapped in a version-named top-level folder.
    # Flatten that one wrapper so the controller can consistently use runtime\bin.
    if(!(Test-Path -LiteralPath (Join-Path $Destination $RequiredFile) -PathType Leaf)) {
        $nested=Get-ChildItem -LiteralPath $Destination -Directory | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName $RequiredFile) -PathType Leaf
        } | Select-Object -First 1
        if($nested) {
            foreach($item in Get-ChildItem -LiteralPath $nested.FullName -Force) {
                $target=Join-Path $Destination $item.Name
                if(Test-Path -LiteralPath $target){throw "Cannot normalize archive layout because a destination already exists: $target"}
                Move-Item -LiteralPath $item.FullName -Destination $target
            }
            Remove-Item -LiteralPath $nested.FullName -Force
        }
    }
    if(!(Test-Path -LiteralPath (Join-Path $Destination $RequiredFile) -PathType Leaf)) {
        throw "Archive extraction completed but the expected file was not found: $RequiredFile"
    }
}

try {
    $pwshDir=Join-Path $Root '.tools\pwsh'
    $runtimeDir=Join-Path $Root 'runtime'
    Expand-VerifiedArchive $powershellArchive $powershellSha $pwshDir 'pwsh.exe'
    Expand-VerifiedArchive $runtimeArchive $runtimeSha $runtimeDir 'bin\llama-kvmem-server.exe'
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'models')|Out-Null
    Write-Host 'Setup complete. The controller will open now.' -ForegroundColor Green
    exit 0
} catch {
    Write-Host "`nSetup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
