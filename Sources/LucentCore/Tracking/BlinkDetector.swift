import Foundation
import CoreGraphics

public final class BlinkDetector: @unchecked Sendable {

    public enum ClickEvent: Equatable, Sendable {
        case leftClick
        case rightClick
        case doubleClick
    }

    // MARK: - Configuration

    /// EAR value below which the eye is considered closed.
    public var earThreshold: Double = 0.2

    /// Maximum blink duration (seconds) to classify as a quick blink / left click.
    public var quickBlinkMaxDuration: Double = 0.3

    /// Maximum blink duration (seconds) to classify as a long blink / right click.
    /// Blinks longer than quickBlinkMaxDuration and shorter than this are right clicks.
    public var longBlinkMaxDuration: Double = 0.8

    /// Time window (seconds) within which two quick blinks are classified as a double-click.
    /// Measured from first blink-open to second blink-open.
    public var doubleBlinkWindow: Double = 1.0

    /// Minimum time (seconds) between any two click events. Prevents rapid re-triggering.
    public var cooldownDuration: Double = 0.75

    /// Minimum EAR drop on the closing frame to distinguish intentional blinks
    /// from slow, natural blinks. Natural blinks have a gentler gradient.
    public var sharpnessThreshold: Double = 0.08

    // MARK: - State

    /// The timestamp passed into the most recent `update` call.
    public private(set) var lastTimestamp: Double = 0.0

    private var previousEAR: Double = 0.3
    private var blinkStartTime: Double?       // nil means the current closure is untracked
    private var isEyeClosed = false
    private var lastClickTime: Double = -1.0
    private var lastQuickBlinkTime: Double = -1.0  // tracks end-time of last quick blink

    public init() {}

    /// Feed a new EAR sample and return any click events produced.
    ///
    /// - Parameters:
    ///   - ear:       Eye Aspect Ratio for this frame.
    ///   - timestamp: Monotonically increasing time in seconds.
    /// - Returns:     Zero or more `ClickEvent` values.
    public func update(ear: Double, timestamp: Double) -> [ClickEvent] {
        defer {
            previousEAR = ear
            lastTimestamp = timestamp
        }

        var events: [ClickEvent] = []

        let wasOpen = !isEyeClosed
        let nowClosed = ear < earThreshold
        let nowOpen   = ear >= earThreshold

        // ── Eye just closed ────────────────────────────────────────────────
        if wasOpen && nowClosed {
            let earDrop = previousEAR - ear
            isEyeClosed = true
            // Only track blinks that close sharply — filters natural slow blinks.
            blinkStartTime = (earDrop >= sharpnessThreshold) ? timestamp : nil

        // ── Eye just opened ────────────────────────────────────────────────
        } else if isEyeClosed && nowOpen {
            isEyeClosed = false

            if let startTime = blinkStartTime {
                let duration = timestamp - startTime

                // Respect cooldown: suppress if a click fired too recently.
                guard timestamp - lastClickTime >= cooldownDuration else {
                    blinkStartTime = nil
                    return events
                }

                if duration < quickBlinkMaxDuration {
                    // Check for double-click (second quick blink within window).
                    if lastQuickBlinkTime > 0,
                       timestamp - lastQuickBlinkTime < doubleBlinkWindow {
                        events.append(.doubleClick)
                        lastClickTime = timestamp
                        lastQuickBlinkTime = -1.0   // reset to avoid triple-click
                    } else {
                        events.append(.leftClick)
                        lastClickTime = timestamp
                        lastQuickBlinkTime = timestamp
                    }
                } else if duration < longBlinkMaxDuration {
                    events.append(.rightClick)
                    lastClickTime = timestamp
                    lastQuickBlinkTime = -1.0
                }
                // Blinks longer than longBlinkMaxDuration are ignored.
            }
            blinkStartTime = nil
        }

        return events
    }

    /// Compute the Eye Aspect Ratio (EAR) from 8 evenly-spaced eye contour points.
    ///
    /// EAR = (‖p1–p7‖ + ‖p2–p6‖) / (2 · ‖p0–p4‖)
    ///
    /// Points are assumed to be ordered clockwise starting from the left corner:
    /// p0 = left corner, p2 = top-center, p4 = right corner, p6 = bottom-center.
    ///
    /// - Parameter eyePoints: Array of at least 8 `CGPoint` values.
    /// - Returns: EAR scalar; ~0.3 for open eyes, ~0.0 for closed eyes.
    public static func computeEAR(eyePoints: [CGPoint]) -> Double {
        guard eyePoints.count >= 8 else { return 0.0 }
        let horizontal = distance(eyePoints[0], eyePoints[4])
        guard horizontal > 0 else { return 0.0 }
        let v1 = distance(eyePoints[1], eyePoints[7])
        let v2 = distance(eyePoints[2], eyePoints[6])
        return (v1 + v2) / (2.0 * horizontal)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
