# Tasks: Sparkle Auto-Update System

## Phase 1: Sparkle Dependency & Infrastructure

- [x] 1.1: Add Sparkle 2.x SPM dependency (from: "2.7.0") to Package.swift
- [x] 1.2: Create Sources/Mori/Update/ directory structure
- [x] 1.3: Add SUPublicEDKey + SUFeedURL to Info.plist in bundle.sh; embed Sparkle.framework + XPC services
- [x] 1.4: Document EdDSA key generation in docs/auto-update.md

## Phase 2: Core Update Logic

- [x] 2.1: Implement UpdateState.swift (state enum + associated data)
- [x] 2.2: Implement UpdateViewModel.swift (ObservableObject, @Published state, computed properties)
- [x] 2.3: Implement UpdateDriver.swift (SPUUserDriver, callback → state, hasUnobtrusiveTarget)
- [x] 2.4: Implement UpdateDelegate.swift (SPUUpdaterDelegate extension, feed URL, install hooks)
- [x] 2.5: Implement UpdateController.swift (SPUUpdater wrapper, Combine sink for force-install)

## Phase 3: Update UI Components

- [x] 3.1: Implement UpdateBadge.swift (progress ring + icons)
- [x] 3.2: Implement UpdatePill.swift (pill button + popover trigger)
- [x] 3.3: Implement UpdatePopoverView.swift (state-specific detail views)
- [x] 3.4: Implement UpdateAccessoryView.swift (NSTitlebarAccessoryViewController)

## Phase 4: App Integration

- [x] 4.1: Wire UpdateController into AppDelegate
- [x] 4.2: Add titlebar accessory to MainWindowController
- [x] 4.3: Add "Check for Updates…" menu item
- [x] 4.4: Register update actions in command palette

## Phase 5: CI & Appcast Pipeline

- [x] 5.1: Create scripts/generate-appcast.sh (download Sparkle binary, sign archive, generate appcast)
- [x] 5.2: Add appcast generation + gh-pages publish to release.yml (build → archive → sign → upload → gh-pages)
- [x] 5.3: Create initial gh-pages branch structure
- [x] 5.4: Update docs/auto-update.md with full release flow

## Phase 6: Localization & Polish

- [x] 6.1: Add new strings to en + zh-Hans Localizable.strings
- [x] 6.2: Apply .localized() to all computed strings in update UI
- [x] 6.3: Build and verify zero warnings (Swift 6 strict concurrency)
- [x] 6.4: Update CHANGELOG.md
