# Mori Remote — Test Plan

## 1. Real-Device Suspend/Resume Testing (Task 7.4)

### Devices & Versions
- iPhone running iOS 17.x (minimum supported version)
- iPhone running iOS 18.x (latest)

### Pre-conditions
- MoriRemoteHost running on Mac connected to relay
- Mori Remote app installed via Xcode (TestFlight for wider testing)
- Active tmux session on Mac

### Test Scenarios

#### 1.1 Clean Background Suspension
1. Pair iOS device via QR code
2. Attach to a tmux session
3. Verify terminal rendering works (type a command, see output)
4. Press Home button / swipe up to background the app
5. **Expected**: App sends `Detach` control message, WebSocket closes cleanly
6. **Verify on Mac**: MoriRemoteHost logs show detach event

#### 1.2 Fast Resume (< 30s)
1. From scenario 1.1, foreground the app within 30 seconds
2. **Expected**: App reconnects using stored session ID from Keychain
3. **Expected**: Connection status shows "Reconnecting..." briefly, then "Connected"
4. **Expected**: Session list appears, previously attached session is available
5. Re-attach and verify terminal state is consistent

#### 1.3 Resume After Session Expiry (> TTL)
1. Background the app
2. Wait longer than the relay's session TTL (default 120 seconds)
3. Foreground the app
4. **Expected**: Reconnect fails (session expired)
5. **Expected**: App navigates to QR scanner for re-pairing

#### 1.4 Suspend During Active Terminal I/O
1. While running a long command (e.g., `find / -name "*.txt" 2>/dev/null`)
2. Background the app mid-output
3. Wait 5 seconds, then foreground
4. **Expected**: Reconnect succeeds, terminal resumes from current state
5. **Expected**: No ghost characters or rendering artifacts

#### 1.5 Rapid Background/Foreground Cycling
1. Background and foreground the app rapidly (5 times in 10 seconds)
2. **Expected**: No crash, no duplicate connections
3. **Expected**: Final state is either connected or cleanly disconnected

#### 1.6 Network Loss During Background
1. Attach to a session
2. Put device in Airplane Mode
3. Background the app
4. Turn off Airplane Mode
5. Foreground the app
6. **Expected**: Reconnect using stored session ID (if within TTL)

#### 1.7 Memory Pressure
1. Attach to a session
2. Open many other apps to trigger memory warnings
3. Return to Mori Remote
4. **Expected**: If app was not terminated, normal resume. If terminated, fresh launch with auto-reconnect attempt.

### Pass Criteria
- Zero crashes across all scenarios on both iOS 17.x and 18.x
- Reconnection succeeds in < 2 seconds when within TTL
- No leaked file descriptors or ghostty surfaces (check Instruments)
- ConnectionStatus UI accurately reflects state transitions

---

## 2. End-to-End Test: Mac + Fly.io + iOS Device (Task 7.5)

### Infrastructure
- Mac running MoriRemoteHost
- Go relay deployed to Fly.io (single region)
- iOS device on cellular or different Wi-Fi network than Mac

### Pre-conditions
- Relay deployed and healthy: `curl https://your-relay.fly.dev/health`
- At least one tmux session running on Mac
- iOS device has Mori Remote installed

### Test Procedure

#### 2.1 Pairing Flow
1. On Mac: `mori-remote-host qrcode --relay-url https://your-relay.fly.dev`
2. Scan QR code with Mori Remote on iOS
3. **Expected**: iOS connects to relay, transitions to session list
4. **Expected**: Mac logs show host paired with viewer
5. **Measure**: Time from scan to session list visible (target: < 3s)

#### 2.2 Session Listing
1. After pairing, verify session list matches `tmux list-sessions` output on Mac
2. Pull-to-refresh and verify list updates
3. **Expected**: Display-friendly names shown (project/branch format)

#### 2.3 Read-Only Mode
1. Tap a session to attach in read-only mode (default)
2. **Expected**: Terminal renders Mac's terminal output
3. Type on Mac terminal, verify iOS display updates
4. **Measure**: RTT (Mac keystroke to iOS render)
5. Try typing on iOS — input should be ignored (read-only)

#### 2.4 Interactive Mode
1. Toggle mode to Interactive via floating button
2. Type a command on iOS (e.g., `echo hello`)
3. **Expected**: Command appears on Mac terminal and iOS terminal
4. **Measure**: RTT (iOS keystroke to iOS render round-trip)
5. Verify Mac terminal size is not constrained by iOS (grouped session)

#### 2.5 High-Throughput Test
1. In interactive mode, run `cat /usr/share/dict/words` (or similar large output)
2. **Expected**: Smooth rendering on iOS, no dropped frames
3. **Expected**: No WebSocket backpressure disconnect for reasonable output
4. **Measure**: Time to render complete output vs Mac

#### 2.6 Orientation Change
1. Rotate iOS device to landscape
2. **Expected**: Resize message sent to relay -> Mac
3. **Expected**: tmux session adjusts to new dimensions
4. Rotate back to portrait and verify

#### 2.7 Detach and Re-attach
1. Tap detach button in terminal view
2. **Expected**: Returns to session list
3. Tap the same session again
4. **Expected**: Re-attaches, terminal state preserved

#### 2.8 Device Revocation
1. Tap menu > "Forget This Device" on iOS
2. **Expected**: Session ID cleared, returns to QR scanner
3. Attempting to reconnect with old session ID should fail

#### 2.9 Relay Restart Recovery
1. While connected, restart the Fly.io relay (`fly machines restart`)
2. **Expected**: iOS shows "Disconnected" or "Reconnecting..."
3. **Expected**: Both Mac and iOS auto-reconnect after relay is back
4. **Measure**: Recovery time from relay restart to connected state

### RTT Measurement Approach

**Method 1: Timestamp echo**
```bash
# On Mac terminal (attached via iOS interactive mode):
while true; do echo "$(date +%s%3N)"; sleep 1; done
```
Compare displayed timestamp on iOS to actual wall clock. Difference includes:
- iOS input -> WebSocket -> relay -> Mac pty -> tmux -> relay -> WebSocket -> iOS render

**Method 2: Screen recording analysis**
1. Screen-record both Mac and iOS simultaneously
2. Type a distinctive character on iOS
3. Count frames between iOS keyboard tap and character appearing on iOS display
4. At 60fps: each frame = ~16.7ms

**Target RTT**: < 100ms on same continent; < 200ms cross-continent

### Pass Criteria
- Complete end-to-end flow works (pair -> list -> attach -> interact -> detach)
- RTT < 100ms for same-region Fly.io deployment
- No data corruption in terminal output
- Relay handles reconnection gracefully
- QR pairing completes in < 3 seconds
- Interactive mode does not constrain Mac terminal size
