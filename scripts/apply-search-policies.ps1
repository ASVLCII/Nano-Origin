[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Runtime)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$policyPath = Join-Path $Runtime 'distribution\policies.json'
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) { throw "Missing policies: $policyPath" }

$doc = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json -Depth 100
$doc.policies.SearchEngines.Add = @(
  [pscustomobject]@{Name='DuckDuckGo No AI';URLTemplate='https://noai.duckduckgo.com/?q={searchTerms}';Method='GET';Alias='@noai';Description='DuckDuckGo without Duck.ai or AI summaries'},
  [pscustomobject]@{Name='Brave Search';URLTemplate='https://search.brave.com/search?q={searchTerms}';Method='GET';Alias='@brave';Description='Brave Search'},
  [pscustomobject]@{Name='Google';URLTemplate='https://www.google.com/search?q={searchTerms}';Method='GET';Alias='@google';Description='Google Search'},
  [pscustomobject]@{Name='DuckDuckGo Onion — requires Tor';URLTemplate='https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/?q={searchTerms}';Method='GET';Alias='@onion';Description='Requires Tor; Nano Origin does not bundle or proxy Tor'}
)
$doc.policies.SearchEngines.Default = 'DuckDuckGo No AI'
$doc.policies.SearchEngines.DefaultPrivate = 'DuckDuckGo No AI'
$doc.policies.SearchEngines.PreventInstalls = $false

$aliases = @($doc.policies.SearchEngines.Add.Alias)
if (@($aliases | Select-Object -Unique).Count -ne $aliases.Count) { throw 'Duplicate search alias.' }
if ($aliases -notcontains '@brave' -or $aliases -notcontains '@google') { throw 'Required search choices missing.' }

[IO.File]::WriteAllText($policyPath,($doc | ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{Policies=$policyPath;Default=$doc.policies.SearchEngines.Default;Aliases=($aliases -join ', ');UserCanAdd=(-not $doc.policies.SearchEngines.PreventInstalls)}

