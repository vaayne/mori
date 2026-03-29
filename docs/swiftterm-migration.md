# SwiftTerm Migration Plan — iOS Only

> Replace GhosttyKit with [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for the MoriRemote iOS app.  
> macOS continues using GhosttyKit — no changes to the desktop target.

## 1. Why

GhosttyKit's iOS surface doesn't render without a backing process (`/bin/sh` etc.), and the iOS simulator has no `/bin`. SwiftTerm is a pure-Swift VT100 emulator + Metal renderer designed for exactly this use case — feeding raw bytes from an SSH channel into a terminal view with no local process.

---

## 2. Dependency Setup

### 2.1 Add SwiftTerm SPM dependency

**File: `Packages/MoriTerminal/Package.swift`**

Add SwiftTerm as a remote package dependency and conditionally link it on iOS only. GhosttyKit remains the macOS dependency.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoriTerminal",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MoriTerminal", targets: ["MoriTerminal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "MoriTerminal",
            dependencies: [
                "GhosttyKit",
                .product(name: "SwiftTerm", package: "SwiftTerm",
                         condition: .when(platforms: [.iOS])),
            ],
            path: "Sources/MoriTerminal",
            linkerSettings: [
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedLibrary("c++"),
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "../../Frameworks/GhosttyKit.xcframework"
        ),
    ]
)
```

> **Note:** If the GhosttyKit xcframework doesn't include an iOS simulator slice, we may need to also make the `GhosttyKit` dependency conditional on macOS. In that case, split the target or use `#if os(iOS)` / `#if os(macOS)` guards around imports. See §6 for cleanup details.

---

## 3. New File: `SwiftTermRenderer.swift`

**Path: `Packages/MoriTerminal/Sources/MoriTerminal/SwiftTermRenderer.swift`**

A thin UIView wrapper around SwiftTerm's `TerminalView` that exposes the same API contract the coordinator already uses:

```
feedBytes(_ data: Data)
gridSize() -> (cols: UInt16, rows: UInt16)
// UIView subclass — embeddable via Auto Layout
```

### Design

```swift
#if os(iOS)
import SwiftTerm
import UIKit

/// Callback fired when the terminal wants to send data back (user keystrokes).
public typealias SwiftTermInputHandler = @MainActor (Data) -> Void

/// Callback fired when the terminal grid dimensions change.
public typealias SwiftTermSizeChangeHandler = @MainActor (UInt16, UInt16) -> Void

@MainActor
public final class SwiftTermRenderer: UIView {

    private let terminalView: TerminalView
    private var inputHandler: SwiftTermInputHandler?
    private var sizeChangeHandler: SwiftTermSizeChangeHandler?

    public init(
        frame: CGRect = .zero,
        inputHandler: SwiftTermInputHandler? = nil,
        sizeChangeHandler: SwiftTermSizeChangeHandler? = nil
    ) {
        self.inputHandler = inputHandler
        self.sizeChangeHandler = sizeChangeHandler
        self.terminalView = TerminalView(frame: frame)
        super.init(frame: frame)

        // Configure terminal appearance
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        terminalView.terminalDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// Feed raw terminal output bytes (from SSH/tmux) into the emulator.
    public func feedBytes(_ data: Data) {
        let bytes = Array(data)
        terminalView.feed(byteArray: bytes)
    }

    /// Current terminal grid dimensions.
    public func gridSize() -> (cols: UInt16, rows: UInt16) {
        let terminal = terminalView.getTerminal()
        return (UInt16(terminal.cols), UInt16(terminal.rows))
    }

    /// Update the input handler (called when user types on the iOS keyboard).
    public func setInputHandler(_ handler: @MainActor @escaping (Data) -> Void) {
        self.inputHandler = handler
    }

    /// Update the size-change handler.
    public func setSizeChangeHandler(_ handler: @MainActor @escaping (UInt16, UInt16) -> Void) {
        self.sizeChangeHandler = handler
    }

    /// Make the embedded terminal view the first responder (show keyboard).
    public func activateKeyboard() {
        terminalView.becomeFirstResponder()
    }
}

// MARK: - TerminalViewDelegate

extension SwiftTermRenderer: TerminalViewDelegate {
    /// Called when the terminal wants to send data (user keystrokes).
    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let d = Data(data)
        inputHandler?(d)
    }

    /// Called when the terminal view resizes its grid.
    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        sizeChangeHandler?(UInt16(newCols), UInt16(newRows))
    }

    /// Called when the terminal title changes (optional, log only).
    public func setTerminalTitle(source: TerminalView, title: String) {
        // No-op for now — could surface in UI later
    }

    /// Required by protocol — no-op.
    public func scrolled(source: TerminalView, position: Double) {}
}
#endif
```

### Key points

- **SwiftTerm handles keyboard input natively** via `UITextInput`. No custom text field or accessory needed.
- **`TerminalViewDelegate.send()`** fires when the user types — we route these bytes back through tmux `send-keys`.
- **`sizeChanged()`** replaces the manual layout-based resize detection.

---

## 4. File-by-File Changes

### 4.1 `TerminalView.swift` (MoriRemote)

**Goal:** Replace `GhosttyiOSRenderer` with `SwiftTermRenderer`.

```swift
import MoriTerminal
import SwiftUI
import UIKit

struct TerminalView: UIViewRepresentable {
    let onRendererReady: @MainActor (SwiftTermRenderer) -> Void

    func makeUIView(context: Context) -> SwiftTermRenderer {
        let renderer = SwiftTermRenderer()
        renderer.backgroundColor = .black
        // Defer callback to next run-loop tick so SwiftUI is settled
        DispatchQueue.main.async {
            onRendererReady(renderer)
            renderer.activateKeyboard()
        }
        return renderer
    }

    func updateUIView(_ uiView: SwiftTermRenderer, context: Context) {
        // No-op — renderer is long-lived, coordinator holds a weak ref
    }
}
```

**Changes:**
- Delete `TerminalContainerView` class entirely — `SwiftTermRenderer` is the UIView itself.
- Remove `onRendererResize` callback — SwiftTerm fires `sizeChanged` via its delegate.
- Call `activateKeyboard()` after ready to auto-show the iOS keyboard.

### 4.2 `SpikeCoordinator.swift`

**Goal:** Replace `GhosttyiOSRenderer` references with `SwiftTermRenderer`. Wire up input and resize handlers.

| Change | Detail |
|--------|--------|
| `import MoriTerminal` | Stays the same |
| `private weak var renderer: GhosttyiOSRenderer?` | → `private weak var renderer: SwiftTermRenderer?` |
| `func attachSession(name:renderer:)` signature | `renderer: SwiftTermRenderer` |
| `func registerRenderer(_:)` | `SwiftTermRenderer` param type |
| `func rendererDidResize(_:)` | **Delete** — replaced by `sizeChangeHandler` |
| New: wire input handler | In `registerRenderer()`, call `renderer.setInputHandler { [weak self] data in self?.sendRawInput(data) }` |
| New: wire size handler | In `registerRenderer()`, call `renderer.setSizeChangeHandler { [weak self] cols, rows in self?.handleSizeChange(cols, rows) }` |
| New: `sendRawInput(_ data: Data)` | Sends raw bytes via tmux `send-keys -l` (convert Data→String, then existing `sendInput()` path) |
| New: `handleSizeChange(_:_:)` | Calls `scheduleCommand("refresh-client -C \(cols),\(rows)")` |
| `sendInput()` / `sendSpecialKey()` | Keep as fallback — but primary input now comes from SwiftTerm delegate |

#### New methods on `SpikeCoordinator`:

```swift
/// Receive raw bytes from SwiftTerm keyboard input and forward to tmux.
func sendRawInput(_ data: Data) {
    guard let paneId = attachedPaneId else { return }
    // tmux send-keys supports hex escapes for raw bytes.
    // For simplicity, convert to string and use send-keys -l.
    guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
    let escapedText = Self.shellQuote(text)
    scheduleCommand("send-keys -l -t \(paneId) \(escapedText)")
}

/// Respond to terminal grid resize from SwiftTerm.
func handleSizeChange(_ cols: UInt16, _ rows: UInt16) {
    guard cols > 0, rows > 0 else { return }
    scheduleCommand("refresh-client -C \(cols),\(rows)")
}
```

### 4.3 `MoriRemoteApp.swift`

**Minimal changes:**

- `TerminalScreen` removes `onRendererResize` from `TerminalView(...)`.
- `TerminalScreen` removes `KeyboardInputView()` from the ZStack — SwiftTerm provides its own keyboard.
- The `TerminalView` callback signature changes from `GhosttyiOSRenderer` to `SwiftTermRenderer`.

```swift
private struct TerminalScreen: View {
    @Environment(SpikeCoordinator.self) private var coordinator
    let sessionName: String
    @State private var attachStarted = false

    var body: some View {
        TerminalView(
            onRendererReady: { renderer in
                coordinator.registerRenderer(renderer)
                guard !attachStarted else { return }
                attachStarted = true
                Task {
                    await coordinator.attachSession(name: sessionName, renderer: renderer)
                }
            }
        )
        .ignoresSafeArea(.keyboard)
        .background(Color.black)
        .overlay {
            if coordinator.isAttachingSession || !coordinator.isTerminalAttached {
                ProgressView("Attaching session...")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}
```

> **Note:** `.ignoresSafeArea(.keyboard)` lets SwiftTerm's `TerminalView` handle its own keyboard avoidance, or we may use `.ignoresSafeArea(edges: .bottom)` and let the view scroll. To be tested.

### 4.4 `KeyboardInputView.swift`

**Delete entirely** or keep as a reduced special-key toolbar.

**Option A (recommended for first pass): Delete.**  
SwiftTerm handles all keyboard input natively including special keys. Remove the file and all references.

**Option B (later enhancement): Keep as floating toolbar.**  
Reduce to just the special-key row (Ctrl+C, arrows, Esc, Tab) overlaid at the top of the keyboard. Wire buttons to `coordinator.sendSpecialKey()`. This can be added back after the core migration is validated.

---

## 5. Keyboard Input Flow (New)

```
┌─────────────────────┐
│  iOS Software        │
│  Keyboard            │
└─────────┬───────────┘
          │ (UITextInput)
          ▼
┌─────────────────────┐
│  SwiftTerm           │
│  TerminalView        │
│  (VT100 emulator)    │
└─────────┬───────────┘
          │ delegate.send(data:)
          ▼
┌─────────────────────┐
│  SwiftTermRenderer   │
│  .inputHandler       │
└─────────┬───────────┘
          │ sendRawInput(data)
          ▼
┌─────────────────────┐
│  SpikeCoordinator    │
│  tmux send-keys -l   │
└─────────┬───────────┘
          │ SSHChannelTransport
          ▼
┌─────────────────────┐
│  Remote tmux server  │
└─────────────────────┘
```

---

## 6. Cleanup

### 6.1 Delete files

| File | Reason |
|------|--------|
| `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyiOSRenderer.swift` | Replaced by `SwiftTermRenderer.swift` |
| `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyiOSApp.swift` | No longer needed — SwiftTerm doesn't need a host app singleton |
| `MoriRemote/MoriRemote/KeyboardInputView.swift` | SwiftTerm handles keyboard natively |

### 6.2 GhosttyKit dependency

The existing `GhosttyiOSRenderer` and `GhosttyiOSApp` are wrapped in `#if os(iOS)`. After deleting those files, GhosttyKit is only used by macOS code. Two options:

**Option A (safe):** Leave `Package.swift` as-is — GhosttyKit still links on iOS but nothing references it. Dead code, but no build breakage.

**Option B (clean):** If GhosttyKit's xcframework lacks an iOS slice (likely, since rendering is broken), make it conditional:

```swift
.target(
    name: "MoriTerminal",
    dependencies: [
        .target(name: "GhosttyKit", condition: .when(platforms: [.macOS])),
        .product(name: "SwiftTerm", package: "SwiftTerm",
                 condition: .when(platforms: [.iOS])),
    ],
    ...
)
```

> Check whether GhosttyKit.xcframework includes `ios-arm64` / `ios-arm64-simulator` slices first. If it does, Option A is fine. If it doesn't and the build fails, Option B is required.

---

## 7. Migration Checklist

- [ ] Add SwiftTerm SPM dependency to `MoriTerminal/Package.swift`
- [ ] Create `SwiftTermRenderer.swift` in `Packages/MoriTerminal/Sources/MoriTerminal/`
- [ ] Update `TerminalView.swift` — use `SwiftTermRenderer`, remove `TerminalContainerView`
- [ ] Update `SpikeCoordinator.swift` — new renderer type, input/resize handlers
- [ ] Update `MoriRemoteApp.swift` — simplify `TerminalScreen`, remove `KeyboardInputView`
- [ ] Delete `KeyboardInputView.swift`
- [ ] Delete `GhosttyiOSRenderer.swift`
- [ ] Delete `GhosttyiOSApp.swift`
- [ ] Verify MoriTerminal package builds for both iOS and macOS
- [ ] Test on iOS simulator
- [ ] Test on physical iOS device

---

## 8. Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| **SwiftTerm `TerminalView` doesn't render on iOS simulator** | Low — it's used in production iOS apps | Test early; it uses Metal which works on Apple Silicon simulators |
| **`feed(byteArray:)` expects clean VT100 and tmux sends garbage** | Low — tmux output is standard VT100/xterm | If issues, check TERM env var is set to `xterm-256color` |
| **Keyboard input encoding mismatch** | Medium — `send(data:)` gives raw bytes, but `send-keys -l` expects printable text | For control chars (Ctrl+C = 0x03), detect non-printable bytes and use `send-keys` without `-l` flag, or send hex-escaped keys |
| **GhosttyKit conditional compilation breaks macOS build** | Low | macOS code doesn't change; only iOS files are modified behind `#if os(iOS)` |
| **SwiftTerm version incompatibility with Swift 6 strict concurrency** | Medium | Pin to a known-good tag; audit `@Sendable` conformances. SwiftTerm may need `@preconcurrency import` |
| **Missing iOS keyboard accessory (Ctrl, arrows, etc.)** | High likelihood users need it | Plan to re-add a minimal toolbar in a follow-up, wired to `SwiftTerm`'s `send()` or use SwiftTerm's built-in `iOSAccessoryView` |

### Testing Strategy

1. **Build verification**: `mise run build` (macOS unchanged), Xcode build for MoriRemote (iOS)
2. **Simulator smoke test**: Launch app → Connect → Attach → verify terminal renders, cursor visible
3. **Keyboard test**: Type characters → verify they appear on remote tmux session
4. **Resize test**: Rotate device → verify `refresh-client` sent, content reflows
5. **Capture-pane test**: Attach to a session that already has content → verify existing content appears
6. **Reconnect test**: Disconnect → reconnect → attach → verify clean state
7. **Physical device test**: Metal rendering on real hardware, keyboard with accessory bar

---

## 9. Commit Plan

| # | Commit | Scope |
|---|--------|-------|
| 1 | `✨ feat: add SwiftTerm dependency and SwiftTermRenderer for iOS` | `Package.swift`, `SwiftTermRenderer.swift` |
| 2 | `♻️ refactor: replace GhosttyKit with SwiftTerm in MoriRemote` | `TerminalView.swift`, `SpikeCoordinator.swift`, `MoriRemoteApp.swift` |
| 3 | `🔥 chore: remove GhosttyKit iOS files and KeyboardInputView` | Delete `GhosttyiOSRenderer.swift`, `GhosttyiOSApp.swift`, `KeyboardInputView.swift` |

Squash-friendly — can be combined into a single commit if preferred.
