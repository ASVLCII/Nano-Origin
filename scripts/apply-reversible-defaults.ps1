[CmdletBinding()]
param(
  [string]$Runtime = 'X:\NanoOriginBuild\rebrand-r1\search-runtime',
  [string]$ProfileSeed = 'X:\NanoOriginBuild\payload\profile-seed'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$policyPath = Join-Path $Runtime 'distribution\policies.json'
$userJsPath = Join-Path $ProfileSeed 'user.js'
$cssPath = Join-Path $ProfileSeed 'chrome\userChrome.css'
foreach ($path in $policyPath,$userJsPath,$cssPath) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing input: $path" }
}

# These are profile defaults only: users may re-enable them in Settings, site
# permissions, or about:config. Do not remove components or lock these prefs.
$defaults = [ordered]@{
  'toolkit.crashreporter.enabled' = $false
  'browser.crashReports.unsubmittedCheck.enabled' = $false
  'app.update.service.enabled' = $false
  'default-browser-agent.enabled' = $false
  'browser.translations.enable' = $false
  'browser.translations.automaticallyPopup' = $false
  'signon.rememberSignons' = $false
  'signon.autofillForms' = $false
  'signon.generation.enabled' = $false
  'extensions.formautofill.addresses.enabled' = $false
  'extensions.formautofill.creditCards.enabled' = $false
  'extensions.formautofill.heuristics.enabled' = $false
  'signon.management.page.breach-alerts.enabled' = $false
  'signon.management.page.vulnerable-passwords.enabled' = $false
  'browser.contentblocking.report.monitor.enabled' = $false
  'browser.contentblocking.report.vpn.enabled' = $false
  'signon.firefoxRelay.feature' = $false
  'media.autoplay.default' = 5
  'permissions.default.camera' = 2
  'permissions.default.microphone' = 2
  'permissions.default.geo' = 2
  'permissions.default.xr' = 2
  'media.eme.enabled' = $false
  'media.gmp-widevinecdm.enabled' = $false
  'screenshots.browser.component.enabled' = $false
  'reader.parse-on-load.enabled' = $false
  'media.videocontrols.picture-in-picture.video-toggle.enabled' = $false
  'media.videocontrols.picture-in-picture.enabled' = $false
  'devtools.chrome.enabled' = $false
  'devtools.debugger.remote-enabled' = $false
  'pdfjs.disabled' = $true
  'browser.tabs.firefox-view' = $false
  'sidebar.revamp' = $false
}

$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
# These two policies prevent ordinary user control, so make them profile defaults.
foreach ($name in 'PasswordManagerEnabled','OfferToSaveLogins') {
  $policy.policies.PSObject.Properties.Remove($name)
}
$policy | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $policyPath -Encoding utf8

$existing = Get-Content -LiteralPath $userJsPath -Raw
foreach ($entry in $defaults.GetEnumerator()) {
  $existing = [regex]::Replace($existing, '(?m)^user_pref\("' + [regex]::Escape($entry.Key) + '".*\r?\n?', '')
}
$lines = foreach ($entry in $defaults.GetEnumerator()) {
  $value = if ($entry.Value -is [bool]) { $entry.Value.ToString().ToLowerInvariant() } else { [string]$entry.Value }
  'user_pref("{0}", {1});' -f $entry.Key,$value
}
Set-Content -LiteralPath $userJsPath -Value ($existing.TrimEnd() + "`r`n" + ($lines -join "`r`n") + "`r`n") -Encoding ascii

# Visible controls must not be hidden by CSS if the user is to turn them back on.
$css = Get-Content -LiteralPath $cssPath -Raw
$css = $css -replace ', #reader-mode-button', '' -replace ', #translations-button', '' -replace ', #picture-in-picture-button', '' -replace ', #firefox-view-button', ''
Set-Content -LiteralPath $cssPath -Value $css -Encoding utf8

[pscustomobject]@{ Defaults=$defaults.Count; Policy=$policyPath; Profile=$userJsPath; Css=$cssPath }
