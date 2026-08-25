# Nano Origin parts 61–70 — search choice

Status: complete in `X:\NanoOriginBuild\rebrand-r1\search-runtime`.

1. Keep DuckDuckGo No AI as normal and private default.
2. Keep `@noai`.
3. Add Brave Search as `@brave`.
4. Add Google as `@google`.
5. Keep the DuckDuckGo onion shortcut as `@onion`.
6. Label onion search as requiring Tor; do not bundle Tor.
7. Allow users to install additional search engines.
8. Keep search suggestions disabled by default.
9. Preserve uBlock Origin and its update path.
10. Verify aliases, defaults, persistence, and performance before promotion.

Verification: policy JSON parses; normal/private defaults are DuckDuckGo No AI; aliases are unique; `PreventInstalls=false`; uBlock remains present; and `browser\omni.ja` is byte-identical to the performance-winning r1 runtime.
