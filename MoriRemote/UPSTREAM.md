# MoriRemote remux upstreams

## remux GhosttyKit (Phase 0 feasibility probe)

MoriRemote's remux rewrite probe uses a separately installed, **untracked**
XCFramework at `Frameworks/RemuxGhosttyKit.xcframework`. It is intentionally
not the macOS framework at `Frameworks/GhosttyKit.xcframework` and must never
replace it.

| Field | Value |
| --- | --- |
| Release asset | `GhosttyKit.xcframework.zip` |
| Release tag | `ghosttykit-20260731` |
| SHA-256 | `e54ca81edf40721f72e87b5a5449746cd8fdcc877d5b0f284cdf2e34609f21f9` |
| Asset repository | <https://github.com/h3nock/remux-ghostty> |
| Asset source commit | `aeb8f73790946d9c9ad175b3dafaec9911ef36bb` |
| Reference application | <https://github.com/h3nock/remux> at `b3a3e5f5dfa4759ab189e203b9a03749e821540c` |

Install it with `scripts/fetch-remux-ghosttykit.sh`, then validate it with
`scripts/verify-remux-ghosttykit.sh`. The scripts enforce the pinned archive
checksum and provenance record, require iOS arm64 device and simulator slices,
and check the custom tmux C ABI before any probe build.

The framework derives from Ghostty as modified by `h3nock/remux-ghostty`.
Ghostty is MIT licensed; its required notice is in
[`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md). The remux application
is also MIT licensed; no remux application source is copied in Phase 0.

Publishing or mirroring this third-party binary is deliberately deferred to
Phase 6. It is not necessary to establish Phase 0 feasibility and would create
an external release obligation before the build gate passes.
