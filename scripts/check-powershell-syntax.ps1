[CmdletBinding()]
param(
  [string]$ScriptsPath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scripts = @(Get-ChildItem -LiteralPath $ScriptsPath -Filter '*.ps1' -File -Recurse)
if ($scripts.Count -eq 0) { throw "No PowerShell scripts found in: $ScriptsPath" }

$invalid = 0
foreach ($script in $scripts) {
  $tokens = $null
  $parseErrors = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile(
    $script.FullName, [ref]$tokens, [ref]$parseErrors
  )
  foreach ($parseError in $parseErrors) {
    $invalid++
    Write-Host ('{0}:{1}:{2}: {3}' -f $script.FullName,
      $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber,
      $parseError.Message)
  }
}

if ($invalid -gt 0) { throw "Found $invalid PowerShell parse error(s)." }
Write-Host "PowerShell syntax passed for $($scripts.Count) scripts."
