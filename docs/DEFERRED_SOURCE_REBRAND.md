# Deferred: source-level Nano Origin rebrand

Status: intentionally deferred for a later range.

## Preserved winner

- Engine/runtime base: original Nano Origin r1 (Firefox ESR 140.14.0).
- Protected runtime: `X:\NanoOriginBuild\rebrand-r1\base-runtime`.
- Winning visible identity layer: `X:\NanoOriginBuild\rebrand-r1\official-icon-runtime`.
- Canonical logo: `X:\NanoOriginBuild\orbit.png`, SHA-256 `3B9DD582785DBDE2EDDC6AB792537A52EEC2F5BF5216738AE5322C80C4118675`.
- Official ICO: seven frames (16, 24, 32, 48, 64, 128, 256).

The official icon gate passed: warm startup improved 6.75%, cold working/private memory fell 5.89%/6.63%, and warm memory fell 2.77%/2.38%. Cold-start improvement is not claimed because its spread widened.

## Rejected and deleted

- Combined icon + PE version metadata: warm startup regressed 45.62%.
- PE version metadata alone: cold/warm memory and CPU regressed beyond the 5% gate.
- Repacked full branding/new-tab omnijar: repeated warm CPU regression; strict promotion failed.
- Repacked brand-only omnijar: warm working set +8.90%, warm private memory +7.31%, quiet CPU +26–38%.

All corresponding runtime copies were deleted. Benchmark JSON/reports remain as evidence.

## Correct later implementation

Perform the full internal name/About/localization rebrand in Firefox source and let Mozilla's build system generate an optimized omnijar. Do not patch or recompress the released `omni.ja`.

Current blocker: no Firefox source checkout, MozillaBuild, Visual Studio/Windows SDK, or clang-cl. C: has only about 1.69 GB free; X: has sufficient capacity. Do not delete unrelated C: data without explicit scope.

