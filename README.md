# Nano Origin

Nano Origin is a compact, privacy-first Windows browser distribution built around Firefox ESR, with uBlock Origin, DuckDuckGo No AI as the default search engine, and a small Orbit visual identity.

This is a community project: it exists to give people a transparent, hackable starting point for a quieter browser—not to operate an account ecosystem, sell attention, or lock users into a vendor service. The project keeps its build scripts, policies, defaults, branding assets, and verification notes in the open so people can inspect, improve, and fork them.

## What it aims to do

- Start from Firefox ESR for a maintained browser engine.
- Keep the interface flat and compact.
- Bundle uBlock Origin and use strict third-party script/frame blocking by default.
- Use DuckDuckGo No AI by default, while retaining Brave, Google, onion, and user-added search choices.
- Disable optional consumer features by default without deleting their components; users can restore them through Firefox Settings, site permissions, or `about:config` where Firefox exposes no normal setting.
- Avoid installer services, automatic browser updates, and unnecessary promotional surfaces.

## Building

The Windows launcher is Go code in `cmd/launcher`. The PowerShell scripts in `scripts/` prepare a Firefox ESR runtime, package a payload, and append it to the native launcher. A Firefox ESR runtime and the signed uBlock Origin XPI are deliberate external build inputs and are not committed here.

Run the launcher tests with:

```powershell
cd cmd/launcher
go test ./...
```

## Licensing

The Nano Origin-original files in this repository are MIT licensed; see [LICENSE](LICENSE).

Nano Origin is not a rewrite of Firefox. Firefox ESR source and binaries are licensed under the Mozilla Public License 2.0, and uBlock Origin has its own license. Those components, their notices, and their licenses remain separate and are not relicensed by this repository. See [NOTICE](NOTICE).

Mozilla and Firefox are trademarks of the Mozilla Foundation. Nano Origin is an independent community project and is not affiliated with or endorsed by Mozilla or the uBlock Origin project.
