[CmdletBinding()]
param(
  [string]$Runtime = 'X:\NanoOriginBuild\rebrand-r1\search-runtime',
  [string]$ProfileSeed = 'X:\NanoOriginBuild\payload\profile-seed'
)

$ErrorActionPreference = 'Stop'
$policyPath = Join-Path $Runtime 'distribution\policies.json'
$userJsPath = Join-Path $ProfileSeed 'user.js'
foreach ($path in $policyPath,$userJsPath) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing input: $path" }
}

$doc = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$doc.policies | Add-Member -NotePropertyName 'Permissions' -NotePropertyValue ([pscustomobject]@{
  Notifications = [pscustomobject]@{BlockNewRequests=$true;Locked=$true}
}) -Force
$prefs = [ordered]@{
  'permissions.default.desktop-notification' = 2
  'dom.webnotifications.enabled' = $false
  'dom.webnotifications.serviceworker.enabled' = $false
  'dom.push.enabled' = $false
  'dom.push.connection.enabled' = $false
  'alerts.useSystemBackend' = $false
  'alerts.useSystemBackend.windows.notificationserver.enabled' = $false
  'browser.messaging-system.whatsNewPanel.enabled' = $false
  'browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features' = $false
  'browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons' = $false
}
foreach ($entry in $prefs.GetEnumerator()) {
  $doc.policies.Preferences | Add-Member -NotePropertyName $entry.Key -NotePropertyValue ([pscustomobject]@{Value=$entry.Value;Status='locked'}) -Force
}
$doc | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $policyPath -Encoding utf8

$lines = foreach ($entry in $prefs.GetEnumerator()) {
  $value = if ($entry.Value -is [bool]) { $entry.Value.ToString().ToLowerInvariant() } else { [string]$entry.Value }
  'user_pref("{0}", {1});' -f $entry.Key,$value
}
$existing = Get-Content -LiteralPath $userJsPath -Raw
foreach ($entry in $prefs.GetEnumerator()) {
  $existing = [regex]::Replace($existing, '(?m)^user_pref\("' + [regex]::Escape($entry.Key) + '".*\r?\n?', '')
}
Set-Content -LiteralPath $userJsPath -Value ($existing.TrimEnd() + "`r`n" + ($lines -join "`r`n") + "`r`n") -Encoding ascii

$notificationHelper = Join-Path $Runtime 'notificationserver.dll'
if (Test-Path -LiteralPath $notificationHelper) { Remove-Item -LiteralPath $notificationHelper -Force }

[pscustomobject]@{
  Policy = $policyPath
  Profile = $userJsPath
  NotificationHelperPresent = Test-Path -LiteralPath $notificationHelper
  LockedPreferences = $prefs.Count
}
