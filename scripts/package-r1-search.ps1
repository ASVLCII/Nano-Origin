[CmdletBinding()]
param(
  [string]$Runtime = 'X:\NanoOriginBuild\rebrand-r1\search-runtime',
  [string]$ProfileSeed = 'X:\NanoOriginBuild\payload\profile-seed',
  [string]$Payload = 'X:\NanoOriginBuild\rebrand-r1\nano-origin-r1-search.zip'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath('X:\NanoOriginBuild\rebrand-r1').TrimEnd('\') + '\'
$stage = [IO.Path]::GetFullPath('X:\NanoOriginBuild\rebrand-r1\package-stage-notifications')
$sevenZip = 'C:\Users\admin\AppData\Local\Microsoft\WindowsApps\7z.exe'

foreach ($required in $Runtime,$ProfileSeed,$sevenZip) {
  if (-not (Test-Path -LiteralPath $required)) { throw "Missing packaging input: $required" }
}
$themeScript = Join-Path $PSScriptRoot 'apply-starlight-theme.ps1'
& $themeScript -ProfileSeed $ProfileSeed | Out-Null
if (-not $stage.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging path.' }
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stage 'runtime'),(Join-Path $stage 'profile-seed') -Force | Out-Null

& robocopy.exe $Runtime (Join-Path $stage 'runtime') /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) { throw "Runtime stage failed: $LASTEXITCODE" }
& robocopy.exe $ProfileSeed (Join-Path $stage 'profile-seed') /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) { throw "Profile stage failed: $LASTEXITCODE" }

$stagedOmni = Get-FileHash -LiteralPath (Join-Path $stage 'runtime\browser\omni.ja') -Algorithm SHA256
$sourceOmni = Get-FileHash -LiteralPath (Join-Path $Runtime 'browser\omni.ja') -Algorithm SHA256
if ($stagedOmni.Hash -ne $sourceOmni.Hash) { throw 'Optimized r1 omnijar changed during staging.' }

Remove-Item -LiteralPath $Payload -Force -ErrorAction SilentlyContinue
Push-Location $stage
try {
  & $sevenZip a -tzip -mx=9 $Payload '.\*' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Payload archive failed: $LASTEXITCODE" }
} finally { Pop-Location }

$listing = (& $sevenZip l $Payload) -join "`n"
foreach ($needle in 'runtime\nano-origin-browser.exe','runtime\browser\omni.ja','runtime\distribution\policies.json','runtime\distribution\extensions\uBlock0@raymondhill.net.xpi','profile-seed\nano-origin.ico','profile-seed\chrome\userChrome.css','profile-seed\chrome\userContent.css','profile-seed\chrome\starlight-v2.png','profile-seed\chrome\tab-sparkle.png','profile-seed\chrome\orbit-matte.png') {
  if ($listing -notmatch [regex]::Escape($needle)) { throw "Payload missing: $needle" }
}

[pscustomobject]@{
  Payload=$Payload
  Bytes=(Get-Item -LiteralPath $Payload).Length
  SHA256=(Get-FileHash -LiteralPath $Payload -Algorithm SHA256).Hash
  RuntimeOmniSHA256=$sourceOmni.Hash
  ProfileUserJsSHA256=(Get-FileHash -LiteralPath (Join-Path $stage 'profile-seed\user.js') -Algorithm SHA256).Hash
}
