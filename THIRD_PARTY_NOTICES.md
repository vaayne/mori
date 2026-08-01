# Third-party notices

MoriRemote bundles this document and `THIRD_PARTY_LICENSES/` in every app
archive. The versions below are the resolved versions in
`MoriRemote/MoriRemote.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Modified Ghostty / remux-ghostty

Mori and MoriRemote statically link the Mori-built universal
`GhosttyKit.xcframework`, compiled from
[remux-ghostty](https://github.com/h3nock/remux-ghostty) source commit
`aeb8f73790946d9c9ad175b3dafaec9911ef36bb` (211 commits atop Ghostty
`b213a72c03b427607b43c89ff4223a7baa079fe8`). The source adds the
`ghostty_tmux_client_*` ABI required by MoriRemote. CI verifies the source
provenance, macOS/iOS slices, iOS 17 compatibility, and ABI before either app
consumes its same-workflow artifact.

Ghostty and the modified distribution are MIT licensed:

> MIT License
>
> Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## remux reference application

MoriRemote adapts selected control, lifecycle, and terminal semantics from
[remux](https://github.com/h3nock/remux) commit
`b3a3e5f5dfa4759ab189e203b9a03749e821540c`. The adapted areas and test
provenance are recorded in `MoriRemote/UPSTREAM.md`.

> MIT License
>
> Copyright (c) 2026 h3nock
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## Citadel

MoriRemote uses [Citadel](https://github.com/h3nock/Citadel) commit
`1d0eadd81d0a521b00ede6663c8b3301f5fc252e`.

> MIT License
>
> Copyright (c) 2022 Orlandos
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## Swift packages linked by MoriRemote

| Package | Resolved revision/version | License / distributed notice |
| --- | --- | --- |
| [BigInt](https://github.com/attaswift/BigInt) | `e07e00fa1fd435143a2dcf8b7eec9a7710b2fdfe` / 5.7.0 | MIT: `THIRD_PARTY_LICENSES/BigInt-MIT.txt` |
| [swift-nio-ssh](https://github.com/h3nock/swift-nio-ssh) | `7588777b8f6439efa1a33117f86cb2729abd864c` | Apache-2.0: `Apache-2.0.txt`; GitHub's recursive tree API for this exact commit contains `LICENSE.txt` and no `NOTICE` file, so no invented package notice is bundled. |
| [swift-asn1](https://github.com/apple/swift-asn1) | `9f542610331815e29cc3821d3b6f488db8715517` / 1.6.0 | Apache-2.0: `Apache-2.0.txt`, `swift-asn1-NOTICE.txt` |
| [swift-atomics](https://github.com/apple/swift-atomics) | `b601256eab081c0f92f059e12818ac1d4f178ff7` / 1.3.0 | Apache-2.0: `Apache-2.0.txt` |
| [swift-collections](https://github.com/apple/swift-collections) | `6675bc0ff86e61436e615df6fc5174e043e57924` / 1.4.1 | Apache-2.0: `Apache-2.0.txt` |
| [swift-crypto](https://github.com/apple/swift-crypto) | `95ba0316a9b733e92bb6b071255ff46263bbe7dc` / 3.15.1 | Apache-2.0: `Apache-2.0.txt`, `swift-crypto-NOTICE.txt` |
| [swift-log](https://github.com/apple/swift-log) | `a878e7f8f46cfc0e1125e565b5c08e7d5272dc9a` / 1.14.0 | Apache-2.0: `Apache-2.0.txt`, `swift-log-NOTICE.txt` |
| [swift-nio](https://github.com/apple/swift-nio) | `558f24a4647193b5a0e2104031b71c55d31ff83a` / 2.97.1 | Apache-2.0: `Apache-2.0.txt`, `swift-nio-NOTICE.txt` |
| [swift-system](https://github.com/apple/swift-system) | `7c6ad0fc39d0763e0b699210e4124afd5041c5df` / 1.6.4 | Apache-2.0: `Apache-2.0.txt` |

`THIRD_PARTY_LICENSES/Apache-2.0.txt` contains the complete Apache License
2.0 text. Every listed notice file comes from the resolved source; trailing whitespace is normalized for distribution.
