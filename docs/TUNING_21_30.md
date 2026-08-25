# Nano Origin tuning experiments — parts 21–30

## Outcome

**Rejected after a seeded A/B benchmark.** No candidate profile or preference fragment is retained. No payload, runtime, policy, candidate executable, package script, delivery artifact, or real profile was changed.

This is preference tuning for Firefox ESR, not a claim of K-Meleon equivalence.

## Inventory and decisions

| Group | Exact preferences tested | Decision and rationale |
|---|---|---|
| Process count | `dom.ipc.processCount=4`; `dom.ipc.processCount.webIsolated=1` | **Reject.** A fixed cap is workload/hardware dependent. In particular, constraining isolated web processes is a poor resource/security trade without a representative multi-site benchmark. Defaults remain adaptive; Fission/site isolation is not disabled. |
| Tab unloading | `browser.tabs.unloadOnLowMemory=true` | **Keep.** Uses Firefox's memory-pressure response rather than imposing a timer or tab-count policy. |
| Speculative networking | `network.prefetch-next=false`; `network.dns.disablePrefetch=true`; `network.predictor.enabled=false`; `network.http.speculative-parallel-limit=0` | **Keep for this privacy-oriented product.** Prevents unsolicited speculative work. This is a privacy/background-I/O choice, not a blanket page-load speed claim. |
| Disk cache | `browser.cache.disk.enable=false`; `browser.cache.offline.enable=false` | **Reject as performance tuning.** It can save disk writes but increases repeat-load network, decoding, CPU, and memory-cache pressure. No packaged-default evidence was found that justifies relying on `browser.cache.offline.enable` in this ESR, so it is not retained. Preserve Firefox defaults unless a separate privacy requirement owns this choice. |
| Animations | `browser.tabs.animate=false`; `browser.fullscreen.animate=false`; `toolkit.cosmeticAnimations.enabled=false` | **Keep.** Removes nonessential browser-chrome work without changing the web-exposed reduced-motion media query. `ui.prefersReducedMotion=1` was removed from the candidate because it is observable by sites and therefore changes fingerprint surface. WebRender remains enabled. |
| Background discovery/tasks | `browser.discovery.enabled=false`; `browser.shopping.experience2023.enabled=false`; `extensions.pocket.enabled=false`; `identity.fxaccounts.enabled=false` | **Keep.** These features are outside Nano Origin's product scope and otherwise create discovery/account/content work. Application updates remain a packaging-policy concern, not part of this fragment. |
| Idle wakeups | None | **Reject lore-only tweaks.** No stable, documented pref with a measurable representative workload was identified. Timer-precision/resist-fingerprinting changes were intentionally avoided because they affect compatibility and fingerprint surface. |

## Guardrails

No retained experiment changes `fission.autostart`, `siteIsolation`, sandbox levels, WebRender, JavaScript/Wasm, cookies/storage, user-agent, reduced-motion reporting, timer precision, canvas, fonts, WebRTC, TLS, downloads, PDF handling, search aliases, policies, or extensions. The source seed therefore continues to carry uBlock and the No-AI/search configuration. The harness does not modify the source seed.

## Reproduction and smoke test

Run:

```powershell
& C:\Users\admin\Documents\Codex\2026-08-20\mak\work\tuning_21_30.ps1
```

For each isolated group, the harness copies the profile seed, removes all prefs under test, adds only that group's exact preferences, then launches the current runtime headlessly against a local HTML/JavaScript fixture. Passing requires a nontrivial screenshot within 30 seconds (and exit code 0 if the process exits naturally). This ESR build can remain alive after producing `-screenshot`, so the harness then terminates only the PID tree it started. Results, timings, natural-exit state, and screenshot sizes are written to `results.json`. All profile variants are deleted after results are recorded.

The smoke test proves startup and basic local rendering. It does not convert noisy one-run elapsed times into performance claims; a representative benchmark harness would be required for that.

## Seeded benchmark and rejection

The updated shared harness was run for five measured cold/warm pairs per arm, plus its unmeasured warmup, against the exact same `X:\NanoOriginBuild\payload\runtime`:

- A: current seed, label `baseline-seeded`, SHA-256 `204CBEEF62C25C7E06F7C256869E3D2F6FD203B35F8CEB647B13CCC39275FB2C`
- B: full candidate seed, label `tuned-seeded`, SHA-256 `57246CF82BAE8B55D85064A7F0DBA3DFBC1DB86DDB58BDDF10E79EC2991C2BE6`
- Candidate differed only by removing `ui.prefersReducedMotion`, `dom.ipc.processCount`, `dom.ipc.processCount.webIsolated`, and `browser.cache.offline.enable`. `browser.cache.disk.enable=false` remained, avoiding a storage-policy confound.
- Durable results: `X:\NanoOriginBuild\benchmarks\11-30\20260825-183802-baseline-seeded` and `X:\NanoOriginBuild\benchmarks\11-30\20260825-184052-tuned-seeded`.

| Metric | Baseline median | Tuned median | Delta | Baseline IQR | Tuned IQR |
|---|---:|---:|---:|---:|---:|
| Cold startup (ms) | 6552.45 | 6357.24 | -2.98% | 499.39 | 127.31 |
| Warm startup (ms) | 1198.93 | 1332.59 | +11.15% | 56.07 | 260.18 |
| Cold working set (bytes) | 854810624 | 801947648 | -6.18% | 46477312 | 85856256 |
| Warm working set (bytes) | 840134656 | 896073728 | +6.66% | 11055104 | 63746048 |
| Cold private bytes | 785858560 | 749735936 | -4.60% | 61620224 | 65642496 |
| Warm private bytes | 788926464 | 853377024 | +8.17% | 10612736 | 69259264 |
| Cold quiet-wait CPU (s) | 0.48 | 0.41 | -14.58% | 0.30 | 0.44 |
| Warm quiet-wait CPU (s) | 0.70 | 0.66 | -5.71% | 0.21 | 0.13 |

Cold startup improved only 2.98%, below the required 5% gate. Warm startup and both warm memory medians materially regressed, with substantially wider spreads. The candidate is therefore rejected. Benchmark profile directories were automatically removed only after JSON was durable; the candidate file and disposable best/profile artifacts were then deleted.
