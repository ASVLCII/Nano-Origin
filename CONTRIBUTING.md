# Contributing to Nano Origin

Thanks for taking a look. Nano Origin is small on purpose, so the most useful contributions are usually specific and testable.

Before starting a large change, open a GitHub Discussion or issue first. It is much easier to agree on the shape of a change than to untangle a big pull request later.

## Good places to start

- Test a fresh launch in Windows Sandbox or a clean VM.
- Check the packaged policies and profile defaults for unexpected locked settings.
- Improve the launcher’s extraction, recovery, or integrity tests.
- Verify the Orbit icon and Nano Origin identity in Explorer, taskbar, Alt-Tab, and window titles.
- Improve the compact UI without adding features that make the browser heavier.
- Review Firefox ESR and uBlock Origin licensing, security, and update assumptions.

Please do not submit Firefox or uBlock Origin binaries to this repository. They are external build inputs with their own licensing and release process.

## Pull requests

Keep a pull request focused. Explain what changed, how you tested it, and any tradeoff that users will notice. Do not weaken Firefox sandboxing, Safe Browsing, HTTPS-only mode, or extension integrity checks just to save resources.

If your change affects packaging, include the before-and-after artifact size and a clean-launch result. If it changes a default, say whether users can turn it back on and where.

## Be kind and be precise

People will disagree about privacy, compatibility, and what counts as bloat. Focus on the behavior and evidence. A small reproducer, a screenshot, or a benchmark is more useful than a long argument.
