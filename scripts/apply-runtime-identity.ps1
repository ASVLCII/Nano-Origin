[CmdletBinding()]
param(
  [string]$Runtime = 'X:\NanoOriginBuild\rebrand-r1\search-runtime',
  [string]$DonorExe = 'X:\NanoOriginBuild\candidates\Nano Origin-r7.exe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$patcher = Join-Path $PSScriptRoot 'patch-pe-version.ps1'
foreach ($path in $Runtime,$DonorExe,$patcher) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing input: $path" }
}
foreach ($name in 'firefox.exe','private_browsing.exe') {
  $exe = Join-Path $Runtime $name
  if (Test-Path -LiteralPath $exe) { & $patcher -ExePath $exe -DonorExePath $DonorExe | Out-Null }
}

$ini = Join-Path $Runtime 'application.ini'
$text = Get-Content -LiteralPath $ini -Raw
$text = $text -replace '(?m)^Vendor=.*$', 'Vendor=Nano Origin'
$text = $text -replace '(?m)^Name=.*$', 'Name=Nano Origin'
$text = $text -replace '(?m)^RemotingName=.*$', 'RemotingName=nano-origin'
Set-Content -LiteralPath $ini -Value $text -Encoding ascii

$old = Join-Path $Runtime 'firefox.exe'
$new = Join-Path $Runtime 'nano-origin-browser.exe'
if (Test-Path -LiteralPath $new) { Remove-Item -LiteralPath $new -Force }
Move-Item -LiteralPath $old -Destination $new
Remove-Item -LiteralPath (Join-Path $Runtime 'firefox.exe.sig') -Force -ErrorAction SilentlyContinue

$info = (Get-Item -LiteralPath $new).VersionInfo
if ($info.ProductName -notlike 'Nano Origin*') { throw "Identity patch did not apply: $($info.ProductName)" }
[pscustomobject]@{ Browser=$new; ProductName=$info.ProductName; FileDescription=$info.FileDescription; ApplicationIni=$ini }
