import QuartzCore
import UIKit

/// Tuning for route-forwarded scrolling, resolved once at startup.
enum GhosttyScrollTuning {
    /// Device-tuned gain for both forwarded scroll routes
    /// (2026-06-12 A/B on iPhone 14 Pro Max): at the legacy 2.0, slow
    /// controlled drags jump ahead of the finger; 1.0 and 1.5 felt
    /// equally calm, and 1.5 preserves more momentum reach per flick.
    /// The alt-screen-cursor route was folded onto the same physics
    /// path afterwards and validated at this gain (man/less on
    /// device), so it shares the value deliberately.
    static let routeForwardedDefaultGain: CGFloat = 1.5

    /// Gain from finger travel to precise scroll units on the
    /// mouse-report route. `REMUX_SCROLL_PRECISE_GAIN` overrides for
    /// on-device feel experiments (clamped; same read-once pattern as
    /// the REMUX_TRACE_* flags).
    static let routeForwardedGain: CGFloat = {
        let fallback = routeForwardedDefaultGain
        guard
            let raw = ProcessInfo.processInfo.environment["REMUX_SCROLL_PRECISE_GAIN"],
            let value = Double(raw), value.isFinite
        else {
            return fallback
        }
        let clamped = CGFloat(min(max(value, 0.5), 4))
        NSLog("Remux scrollTuning preciseGain=%.2f (env override)", clamped)
        return clamped
    }()
}

/// Physics engine for route-forwarded (mouse-report) scrolling.
///
/// A hit-test transparent `UIScrollView` with a large virtual content
/// area: its pan gesture and native deceleration produce contentOffset
/// changes that the scroll container converts into the same precise
/// scroll events a trackpad would produce, including the momentum tail
/// after the finger lifts. The view renders nothing and never receives
/// touches itself — the container attaches this view's pan gesture
/// recognizer to itself, so the scroll view acts purely as UIKit's
/// scroll physics driver (the Blink Shell pattern).
final class GhosttyScrollPhysicsView: UIScrollView {
    /// Virtual content height as a multiple of the viewport. Large
    /// enough that a single fling cannot reach an edge before the
    /// container recenters between gestures.
    private static let virtualSpanMultiplier: CGFloat = 9

    /// Touches pass through to the surface view; this view only exists
    /// so UIKit scroll physics run.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    var centeredContentOffsetY: CGFloat {
        max(0, (contentSize.height - bounds.height) / 2)
    }

    /// Keep the virtual content proportional to the viewport so the
    /// deceleration runway scales with the screen.
    func synchronizeVirtualContent() {
        let size = CGSize(
            width: max(bounds.width, 1),
            height: max(bounds.height, 1) * Self.virtualSpanMultiplier
        )
        guard contentSize != size else { return }
        contentSize = size
    }
}

/// Velocity-mapped gain for forwarded scrolling — the standard input
/// acceleration shape (macOS scroll/pointer acceleration works the
/// same way): a pure, monotonic function of smoothed instantaneous
/// velocity. Below `slowVelocity` the multiplier is exactly 1 so the
/// device-tuned slow-drag feel is untouched; above it the multiplier
/// ramps linearly to `maxMultiplier` at `fastVelocity`, giving hard
/// flicks real reach on routes where one tick is a single line.
/// Deterministic: the same gesture at the same speed always scrolls
/// the same amount (the EMA only suppresses single-frame spikes).
struct GhosttyScrollVelocityGain {
    /// Below this speed (points/s) the multiplier is 1: slow,
    /// controlled drags keep the validated 1:1-ish mapping.
    static let slowVelocity: Double = 900
    /// Speed at which the ramp reaches `maxMultiplier`.
    static let fastVelocity: Double = 3_500
    static let maxMultiplier: Double = 3.5

    private let smoothing: Double
    private var smoothedSpeed: Double?
    private var lastSampleTime: TimeInterval?

    init(smoothing: Double = 0.3) {
        self.smoothing = min(max(smoothing, 0.01), 1)
    }

    /// Multiplier for one offset delta (points) observed at `now`.
    mutating func multiplier(delta: Double, at now: TimeInterval) -> Double {
        defer { lastSampleTime = now }
        guard let lastSampleTime else { return 1 }
        let dt = now - lastSampleTime
        guard dt > 0 else { return Self.multiplier(forVelocity: smoothedSpeed ?? 0) }

        let speed = abs(delta) / dt
        let smoothed = (smoothedSpeed ?? speed) * (1 - smoothing) + speed * smoothing
        smoothedSpeed = smoothed
        return Self.multiplier(forVelocity: smoothed)
    }

    /// The pure mapping: 1 below the slow knee, linear ramp to the
    /// cap at the fast knee.
    static func multiplier(forVelocity velocity: Double) -> Double {
        guard velocity > slowVelocity else { return 1 }
        guard velocity < fastVelocity else { return maxMultiplier }
        let t = (velocity - slowVelocity) / (fastVelocity - slowVelocity)
        return 1 + t * (maxMultiplier - 1)
    }

    mutating func reset() {
        smoothedSpeed = nil
        lastSampleTime = nil
    }
}

/// Detects when a deceleration has slowed below the cell-quantization
/// floor. Native scrolling coasts to sub-pixel speeds, but forwarded
/// scrolling emits whole cells: below a couple of cells per second the
/// tail degenerates into isolated ticks hundreds of milliseconds apart
/// — perceived as jitter, not motion. Velocity is smoothed with an
/// exponential moving average so a single short frame cannot trigger
/// a premature stop.
struct GhosttyScrollTailCutoff {
    /// Smoothed speed below which the coast is pure noise, in cells
    /// per second. Discrete whole-cell steps read as motion at ~6+
    /// ticks/s; slower than that the tail is stutter, not glide.
    static let minimumCellsPerSecond: Double = 6

    private let smoothing: Double
    private var smoothedSpeed: Double?
    private var lastSampleTime: TimeInterval?

    init(smoothing: Double = 0.3) {
        self.smoothing = min(max(smoothing, 0.01), 1)
    }

    /// Feed one offset delta (points) observed at `now`; returns true
    /// when the smoothed speed has fallen below the floor.
    mutating func shouldStop(
        delta: Double,
        at now: TimeInterval,
        cellHeightPoints: Double
    ) -> Bool {
        defer { lastSampleTime = now }
        guard let lastSampleTime else { return false }
        let dt = now - lastSampleTime
        guard dt > 0, cellHeightPoints > 0 else { return false }

        let speed = abs(delta) / dt
        let smoothed = (smoothedSpeed ?? speed) * (1 - smoothing) + speed * smoothing
        smoothedSpeed = smoothed
        return smoothed < Self.minimumCellsPerSecond * cellHeightPoints
    }

    mutating func reset() {
        smoothedSpeed = nil
        lastSampleTime = nil
    }
}

/// Token-bucket cap on route-forwarded scroll throughput, in gesture
/// translation units (points). A violent fling decelerates from very
/// high velocity; without a cap one gesture could enqueue an unbounded
/// stream of wheel reports, each of which costs the remote TUI a full
/// repaint. Excess delta is dropped, not deferred: flicks saturate at
/// the cap instead of stretching the scroll out in time.
struct GhosttyScrollDeltaBudget {
    /// Default burst window. Device traces (2026-06-12) showed 0.25s
    /// lets a violent flick dump ~37 one-line ticks instantly — a
    /// near-full-screen teleport before steady-rate pacing kicks in.
    /// ~0.08s bounds the initial dump to a few lines while leaving
    /// gesture-start latency imperceptible.
    static let defaultBurstSeconds: Double = 0.08

    private(set) var unitsPerSecond: Double
    private let burstSeconds: Double
    private var available: Double
    private var lastRefill: TimeInterval?

    init(unitsPerSecond: Double, burstSeconds: Double = Self.defaultBurstSeconds) {
        self.unitsPerSecond = max(unitsPerSecond, 0)
        self.burstSeconds = max(burstSeconds, 0)
        self.available = self.unitsPerSecond * self.burstSeconds
        self.lastRefill = nil
    }

    /// Clamp a signed delta against the remaining budget, refilled by
    /// the time elapsed since the previous call.
    mutating func clamp(_ delta: Double, at now: TimeInterval) -> Double {
        let capacity = unitsPerSecond * burstSeconds
        if let lastRefill {
            let elapsed = max(0, now - lastRefill)
            available = min(available + elapsed * unitsPerSecond, capacity)
        }
        lastRefill = now

        guard delta != 0, available > 0 else { return 0 }
        let magnitude = min(abs(delta), available)
        available -= magnitude
        return delta < 0 ? -magnitude : magnitude
    }

    /// Re-arm for a new gesture with a freshly computed rate (the cap
    /// depends on the surface's cell height, which can change).
    mutating func rearm(unitsPerSecond: Double) {
        self.unitsPerSecond = max(unitsPerSecond, 0)
        self.available = self.unitsPerSecond * burstSeconds
        self.lastRefill = nil
    }
}
