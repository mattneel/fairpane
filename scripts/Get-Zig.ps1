# Install the exact repository compiler without changes to the global PATH.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Lock = Get-Content -LiteralPath (Join-Path $Root 'toolchains/zig.lock.json') -Raw | ConvertFrom-Json
if ($Lock.schema_version -ne 1 -or $Lock.channel -ne 'master') { throw 'The compiler lock must select Zig master.' }
if ($Lock.version -notmatch '^\d+\.\d+\.\d+-dev\.\d+\+[a-f0-9]+$') { throw 'The compiler version is not an exact development version.' }
if ($Lock.source -ne 'https://ziglang.org/download/index.json') { throw 'The compiler lock source is not the official index.' }
$NativeArch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $NativeArch = $env:PROCESSOR_ARCHITEW6432 }
switch ($NativeArch) {
    'AMD64' { $Platform = 'x86_64-windows' }
    'ARM64' { $Platform = 'aarch64-windows' }
    default { throw "No locked Windows compiler exists for architecture $NativeArch." }
}
$Property = $Lock.platforms.PSObject.Properties[$Platform]
if ($null -eq $Property) { throw "The lock does not contain $Platform." }
$Artifact = $Property.Value
$ArchiveRoot = "zig-$Platform-$($Lock.version)"
$ExpectedUrl = "https://ziglang.org/builds/$ArchiveRoot.zip"
if ($Artifact.url -ne $ExpectedUrl -or $Artifact.archive_root -ne $ArchiveRoot) { throw 'The locked archive URL or root is unexpected.' }
if ($Artifact.sha256 -notmatch '^[a-f0-9]{64}$' -or [long]$Artifact.size -le 0) { throw 'The locked archive checksum or size is invalid.' }

function Assert-LocalPath([string]$Relative) {
    $Current = $Root
    foreach ($Component in ($Relative -split '/')) {
        if (-not $Component -or $Component -eq '..' -or $Component -eq '.' -or $Component.Contains(':')) { throw 'Invalid local installation path.' }
        $Current = Join-Path $Current $Component
        if (Test-Path -LiteralPath $Current) {
            $Item = Get-Item -LiteralPath $Current -Force
            if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "A reparse point is not accepted: $Current" }
        }
    }
    return $Current
}
function Assert-Compiler([string]$Executable) {
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'The extracted compiler is absent.' }
    $Actual = & $Executable version
    if ($LASTEXITCODE -ne 0 -or (($Actual -join "`n").Trim()) -ne $Lock.version) { throw 'The compiler version does not match the lock.' }
}
# Hash through .NET because an inherited PowerShell 7 module path can hide Get-FileHash in Windows PowerShell 5.1.
function Get-Sha256([string]$File) {
    $Stream = [IO.File]::OpenRead($File)
    try {
        $Algorithm = [Security.Cryptography.SHA256]::Create()
        try { $Digest = $Algorithm.ComputeHash($Stream) } finally { $Algorithm.Dispose() }
    } finally { $Stream.Dispose() }
    return ([BitConverter]::ToString($Digest) -replace '-', '').ToLowerInvariant()
}
function Assert-Archive([string]$File) {
    if ((Get-Item -LiteralPath $File).Length -ne [long]$Artifact.size) { throw 'The compiler archive size does not match the lock.' }
    if ((Get-Sha256 $File) -ne $Artifact.sha256) { throw 'The compiler archive SHA-256 does not match the lock.' }
}

$Destination = Assert-LocalPath ".tools/zig/$($Lock.version)/$Platform"
$Compiler = Join-Path $Destination 'zig.exe'
if (Test-Path -LiteralPath $Destination) {
    Assert-Compiler $Compiler
    Write-Output $Compiler
    return
}
$Downloads = Assert-LocalPath '.tools/downloads'
[IO.Directory]::CreateDirectory($Downloads) | Out-Null
$Archive = Join-Path $Downloads "$ArchiveRoot.zip"
if (-not (Test-Path -LiteralPath $Archive)) {
    $Partial = "$Archive.$([Guid]::NewGuid().ToString('N')).partial"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $ExpectedUrl -UseBasicParsing -OutFile $Partial -TimeoutSec 600 -MaximumRedirection 0
        Assert-Archive $Partial
        Move-Item -LiteralPath $Partial -Destination $Archive
    } finally {
        if (Test-Path -LiteralPath $Partial) { Remove-Item -LiteralPath $Partial -Force }
    }
}
Assert-Archive $Archive

Add-Type -AssemblyName System.IO.Compression.FileSystem
$Zip = [IO.Compression.ZipFile]::OpenRead($Archive)
try {
    if ($Zip.Entries.Count -eq 0) { throw 'The compiler archive is empty.' }
    foreach ($Entry in $Zip.Entries) {
        $Name = $Entry.FullName.Replace('\', '/').TrimEnd('/')
        if ($Name -ne $ArchiveRoot -and -not $Name.StartsWith("$ArchiveRoot/", [StringComparison]::Ordinal)) { throw 'The compiler archive contains an unexpected root.' }
        if ($Name.StartsWith('/') -or $Name.Contains(':') -or ($Name -split '/') -contains '..') { throw 'The compiler archive contains an unsafe path.' }
    }
} finally { $Zip.Dispose() }

$Parent = Split-Path -Parent $Destination
[IO.Directory]::CreateDirectory($Parent) | Out-Null
$Stage = Join-Path $Parent ".extract-$([Guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($Stage) | Out-Null
try {
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Stage)
    $Extracted = Join-Path $Stage $ArchiveRoot
    Assert-Compiler (Join-Path $Extracted 'zig.exe')
    Move-Item -LiteralPath $Extracted -Destination $Destination
} finally {
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
}
Assert-Compiler $Compiler
$Receipt = [ordered]@{ version = $Lock.version; platform = $Platform; archive_sha256 = $Artifact.sha256; source = $ExpectedUrl }
$Receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Destination 'fairpane-install.json') -Encoding UTF8
Write-Output $Compiler
