[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ProfileSeed
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$profile = [IO.Path]::GetFullPath($ProfileSeed)
$userJs = Join-Path $profile 'user.js'
$chrome = Join-Path $profile 'chrome'
$assets = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\theme'
$orbit = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\newtab\orbit.png'

foreach ($path in @($userJs,$orbit,(Join-Path $assets 'userChrome.css'),(Join-Path $assets 'userContent.css'),(Join-Path $assets 'starlight-v2.png'),(Join-Path $assets 'tab-sparkle.png'))) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing theme input: $path" }
}

New-Item -ItemType Directory -Path $chrome -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $assets 'userChrome.css') -Destination (Join-Path $chrome 'userChrome.css') -Force
Copy-Item -LiteralPath (Join-Path $assets 'userContent.css') -Destination (Join-Path $chrome 'userContent.css') -Force
Copy-Item -LiteralPath (Join-Path $assets 'starlight-v2.png') -Destination (Join-Path $chrome 'starlight-v2.png') -Force
Copy-Item -LiteralPath (Join-Path $assets 'tab-sparkle.png') -Destination (Join-Path $chrome 'tab-sparkle.png') -Force
Copy-Item -LiteralPath $orbit -Destination (Join-Path $chrome 'orbit-matte.png') -Force

# Apply these to the package's profile seed. Sidebar preferences are left alone,
# so this theme does not turn on the optional vertical tab sidebar.
$defaults = [ordered]@{
  'toolkit.legacyUserProfileCustomizations.stylesheets' = 'true'
  'ui.systemUsesDarkTheme' = '1'
  'extensions.activeThemeID' = '"firefox-compact-dark@mozilla.org"'
  'browser.startup.homepage' = '"about:home"'
}
$lines = @(Get-Content -LiteralPath $userJs)
foreach ($name in $defaults.Keys) {
  $lines = @($lines | Where-Object { $_ -notmatch ('^user_pref\("' + [regex]::Escape($name) + '"') })
}
$lines += foreach ($entry in $defaults.GetEnumerator()) {
  'user_pref("{0}", {1});' -f $entry.Key,$entry.Value
}
[IO.File]::WriteAllLines($userJs,$lines,[Text.Encoding]::ASCII)

[pscustomobject]@{
  ProfileSeed = $profile
  ThemeFiles = @('userChrome.css','userContent.css','starlight-v2.png','tab-sparkle.png','orbit-matte.png')
  SidebarDefault = 'unchanged'
}
