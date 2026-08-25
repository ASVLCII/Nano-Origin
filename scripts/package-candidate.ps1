[CmdletBinding()]
param(
    [string]$BundleId = 'esr140.14.0-ubo1.73.0-r4',
    [string]$PayloadPath = 'X:\NanoOriginBuild\payload.zip',
    [string]$OutputPath = 'X:\NanoOriginBuild\candidates\Nano Origin.exe',
    [string]$ExpectedPayloadHash = '25750FF1AE036C031B313029DC8113F207D3D6B126859A5BCBA589306753CA66'
)

$ErrorActionPreference = 'Stop'
$build = 'X:\NanoOriginBuild'
$source = Join-Path $PSScriptRoot 'launcher'
$go = Join-Path $build 'go2\go\bin\go.exe'
$versionTool = Join-Path $build 'gobin\goversioninfo.exe'
$payload = [IO.Path]::GetFullPath($PayloadPath)
$candidateDir = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
$launcher = Join-Path $candidateDir 'Nano Origin.launcher.exe'
$output = [IO.Path]::GetFullPath($OutputPath)
$magic = 'NANOORIGINPKG1!!'
$footerSize = 96

if ($BundleId.Length -gt 32 -or $BundleId.Length -eq 0) { throw 'BundleId must contain 1–32 ASCII characters.' }
if ($BundleId -notmatch '^[\x20-\x7E]+$') { throw 'BundleId must be printable ASCII.' }
foreach ($required in $go,$versionTool,$payload,(Join-Path $source 'main.go'),(Join-Path $source 'versioninfo.json')) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing build input: $required" }
}
$payloadHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $payload).Hash
if ($ExpectedPayloadHash -and $payloadHash -ne $ExpectedPayloadHash) { throw "Payload hash changed unexpectedly: $payloadHash" }

New-Item -ItemType Directory -Force -Path $candidateDir | Out-Null
$env:GOCACHE = Join-Path $build 'gocache2'
$env:GOMODCACHE = Join-Path $build 'gomodcache'
$env:GOTMPDIR = Join-Path $build 'gotmp'
$env:TEMP = Join-Path $build 'tmp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force -Path $env:GOCACHE,$env:GOMODCACHE,$env:GOTMPDIR,$env:TEMP | Out-Null

Push-Location $source
try {
    & $go fmt .
    if ($LASTEXITCODE -ne 0) { throw 'go fmt failed' }
    & $go test ./...
    if ($LASTEXITCODE -ne 0) { throw 'go test failed' }
    & $versionTool -64
    if ($LASTEXITCODE -ne 0) { throw 'version-resource generation failed' }
    & $go build -trimpath -ldflags '-H windowsgui -s -w -buildid=' -o $launcher .
    if ($LASTEXITCODE -ne 0) { throw 'launcher build failed' }
} finally {
    Pop-Location
}

$launcherInfo = Get-Item -LiteralPath $launcher
$payloadInfo = Get-Item -LiteralPath $payload
$bundleBytes = [Text.Encoding]::ASCII.GetBytes($BundleId)
$bundleField = [byte[]]::new(32)
[Array]::Copy($bundleBytes, $bundleField, $bundleBytes.Length)
$shaBytes = [Convert]::FromHexString($payloadHash)
$magicBytes = [Text.Encoding]::ASCII.GetBytes($magic)

$outStream = [IO.File]::Open($output, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $launcherStream = [IO.File]::OpenRead($launcher)
    try { $launcherStream.CopyTo($outStream) } finally { $launcherStream.Dispose() }
    $payloadStream = [IO.File]::OpenRead($payload)
    try { $payloadStream.CopyTo($outStream) } finally { $payloadStream.Dispose() }
    $outStream.Write($magicBytes, 0, $magicBytes.Length)
    $outStream.Write($bundleField, 0, $bundleField.Length)
    $writer = [IO.BinaryWriter]::new($outStream, [Text.Encoding]::ASCII, $true)
    $writer.Write([uint64]$launcherInfo.Length)
    $writer.Write([uint64]$payloadInfo.Length)
    $writer.Flush()
    $outStream.Write($shaBytes, 0, $shaBytes.Length)
    $outStream.Flush($true)
} finally {
    $outStream.Dispose()
}

# Independently parse the written footer and stream-hash the embedded payload.
$check = [IO.File]::OpenRead($output)
try {
    if ($check.Length -lt $footerSize) { throw 'Candidate is shorter than its footer.' }
    $check.Seek(-$footerSize, [IO.SeekOrigin]::End) | Out-Null
    $reader = [IO.BinaryReader]::new($check, [Text.Encoding]::ASCII, $true)
    $actualMagic = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(16))
    $actualBundle = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(32)).TrimEnd([char]0)
    $actualOffset = $reader.ReadUInt64()
    $actualLength = $reader.ReadUInt64()
    $actualSha = $reader.ReadBytes(32)
    if ($actualMagic -ne $magic -or $actualBundle -ne $BundleId) { throw 'Candidate footer identity mismatch.' }
    if ($actualOffset -ne [uint64]$launcherInfo.Length -or $actualLength -ne [uint64]$payloadInfo.Length) { throw 'Candidate footer bounds mismatch.' }

    $check.Seek([int64]$actualOffset, [IO.SeekOrigin]::Begin) | Out-Null
    $hasher = [Security.Cryptography.SHA256]::Create()
    $buffer = [byte[]]::new(1MB)
    $remaining = [int64]$actualLength
    while ($remaining -gt 0) {
        $read = $check.Read($buffer, 0, [Math]::Min($buffer.Length, $remaining))
        if ($read -le 0) { throw 'Unexpected end of embedded payload.' }
        $null = $hasher.TransformBlock($buffer, 0, $read, $null, 0)
        $remaining -= $read
    }
    $null = $hasher.TransformFinalBlock([byte[]]::new(0), 0, 0)
    if ([Convert]::ToHexString($hasher.Hash) -ne [Convert]::ToHexString($actualSha)) { throw 'Embedded payload SHA-256 mismatch.' }
} finally {
    $check.Dispose()
}

$candidateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash
$version = (Get-Item -LiteralPath $output).VersionInfo
[pscustomobject]@{
    Candidate = $output
    BundleId = $BundleId
    Bytes = (Get-Item -LiteralPath $output).Length
    SHA256 = $candidateHash
    PayloadSHA256 = $payloadHash
    FileDescription = $version.FileDescription
    ProductName = $version.ProductName
    Signature = (Get-AuthenticodeSignature -LiteralPath $output).Status
} | Format-List
