import Foundation
import CoreGraphics

// MARK: - Fusion Result

/// Output of the PolyMouse fusion system.
public struct FusionResult: Sendable {
    /// Normalized 0-1 gaze position.
    public let position: GazePoint
    /// When true, the cursor should teleport (Kalman reset) instead of smooth-transition.
    public let isTeleport: Bool
}

// MARK: - Fusion State

public enum FusionState: Sendable {
    /// Waiting for the first saccade.
    case idle
    /// Eyes just jumped — cursor teleports to the eye target.
    case saccade
    /// Head is refining the cursor position after a saccade landed.
    case refining
}

// MARK: - Saccade Detector

/// Detects rapid eye movements (saccades) from pupil positions.
/// Uses a 3-frame velocity window to distinguish deliberate eye jumps
/// from noise. A saccade triggers when the pupil moves faster than
/// the threshold over multiple consecutive frames.
public final class SaccadeDetector: @unchecked Sendable {
    /// Minimum average velocity to trigger a saccade.
    /// Lower = more sensitive. Vision landmarks are noisy so this
    /// needs to be above the noise floor (~0.01) but below real
    /// saccade speed (~0.04+).
    public var threshold: Double = 0.025

    /// Cooldown frames after a saccade before detecting another.
    public var cooldownFrames: Int = 6

    /// Ring buffer of recent pupil positions for velocity averaging.
    private var history: [(x: Double, y: Double)] = []
    private let historySize = 4
    private var cooldownCounter: Int = 0

    public init() {}

    public struct Result: Sendable {
        public let detected: Bool
        public let targetRelX: Double
        public let targetRelY: Double
    }

    public func check(relPupilX: Double, relPupilY: Double) -> Result {
        defer {
            history.append((relPupilX, relPupilY))
            if history.count > historySize { history.removeFirst() }
            if cooldownCounter > 0 { cooldownCounter -= 1 }
        }

        guard !history.isEmpty else {
            return Result(detected: false, targetRelX: relPupilX, targetRelY: relPupilY)
        }

        // Velocity between last known position and current
        let last = history.last!
        let dx = relPupilX - last.x
        let dy = relPupilY - last.y
        let instantVelocity = (dx * dx + dy * dy).squareRoot()

        // Overall displacement from oldest entry to current
        let first = history.first!
        let displacement = ((relPupilX - first.x) * (relPupilX - first.x) +
                           (relPupilY - first.y) * (relPupilY - first.y)).squareRoot()

        let avgVelocity = instantVelocity

        // Saccade = high velocity AND significant displacement
        // (avoids false triggers from jitter which has high velocity but low displacement)
        if avgVelocity > threshold && displacement > threshold * 1.5 && cooldownCounter == 0 {
            cooldownCounter = cooldownFrames
            history.removeAll()  // Clear history after saccade
            return Result(detected: true, targetRelX: relPupilX, targetRelY: relPupilY)
        }

        return Result(detected: false, targetRelX: relPupilX, targetRelY: relPupilY)
    }

    public func reset() {
        history.removeAll()
        cooldownCounter = 0
    }
}

// MARK: - Head Tracker

/// Tracks face bounding box center for fine cursor control.
/// Uses auto-centering so the user's natural head position = "no movement".
/// Returns a delta offset (how far the head moved from neutral).
public final class HeadTracker: @unchecked Sendable {
    /// How much head movement maps to cursor movement.
    /// Higher = more responsive head tracking.
    public var headGain: Double = 3.0

    /// EMA alpha for updating the neutral center (slow drift).
    public var centerAlpha: Double = 0.003

    /// EMA alpha during warmup (fast adaptation).
    public var warmupAlpha: Double = 0.15

    /// Frames until warmup completes.
    public var warmupFrames: Int = 45

    private var centerX: Double = 0.5
    private var centerY: Double = 0.5
    private var framesSeen: Int = 0

    public init() {}

    /// Update with the current face center position (normalized 0-1 in camera frame).
    /// Returns (deltaX, deltaY) — how far from neutral, scaled by headGain.
    public func update(faceCenterX: Double, faceCenterY: Double) -> (dx: Double, dy: Double) {
        framesSeen += 1
        let alpha = framesSeen < warmupFrames ? warmupAlpha : centerAlpha

        centerX += alpha * (faceCenterX - centerX)
        centerY += alpha * (faceCenterY - centerY)

        let dx = (faceCenterX - centerX) * headGain
        let dy = (faceCenterY - centerY) * headGain

        return (dx, dy)
    }

    public func reset() {
        centerX = 0.5
        centerY = 0.5
        framesSeen = 0
    }
}

// MARK: - PolyMouse Fusion

/// Two-channel fusion: eyes for coarse target acquisition, head for fine refinement.
///
/// Flow:
/// 1. Eyes detect saccade → cursor teleports to gaze target region
/// 2. Head refines position → smooth, precise cursor movement
/// 3. Eyes detect another saccade → cycle repeats
public final class PolyMouseFusion: @unchecked Sendable {
    public private(set) var state: FusionState = .idle
    public let saccadeDetector = SaccadeDetector()
    public let headTracker = HeadTracker()

    /// Current cursor position in normalized 0-1 coordinates.
    private var currentPosition = GazePoint(x: 0.5, y: 0.5)

    /// How much of the screen the eye saccade target covers.
    /// The eye target determines a region, not a pixel.
    /// This scales the eye-target-to-screen mapping.
    public var eyeRegionScale: Double = 1.0

    public init() {}

    /// Process one frame of tracking data.
    /// - Parameters:
    ///   - faceBounds: Face bounding box in normalized image coordinates.
    ///   - leftPupil: Left pupil position in normalized image coordinates.
    ///   - rightPupil: Right pupil position in normalized image coordinates.
    /// - Returns: Fusion result with position and teleport flag.
    public func update(faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> FusionResult {
        // Compute pupil position relative to face bounding box
        let pupilMidX = Double(leftPupil.x + rightPupil.x) / 2.0
        let pupilMidY = Double(leftPupil.y + rightPupil.y) / 2.0
        let faceW = max(Double(faceBounds.width), 0.001)
        let faceH = max(Double(faceBounds.height), 0.001)
        let relX = (pupilMidX - Double(faceBounds.minX)) / faceW
        let relY = (pupilMidY - Double(faceBounds.minY)) / faceH

        // Check for saccade
        let saccade = saccadeDetector.check(relPupilX: relX, relPupilY: relY)

        // Head tracking (always updates, even during saccade)
        // Mirror X for front-facing camera
        let headX = 1.0 - Double(faceBounds.midX)
        let headY = Double(faceBounds.midY)
        let headDelta = headTracker.update(faceCenterX: headX, faceCenterY: headY)

        if saccade.detected {
            state = .saccade

            // Map eye target to screen region.
            // The pupil-relative position indicates gaze direction:
            //   relX < 0.5 = looking right (mirrored camera)
            //   relX > 0.5 = looking left
            //   relY < 0.5 = looking up
            //   relY > 0.5 = looking down
            let eyeTargetX = (1.0 - saccade.targetRelX) * eyeRegionScale
            let eyeTargetY = saccade.targetRelY * eyeRegionScale

            currentPosition = GazePoint(
                x: min(max(eyeTargetX, 0), 1),
                y: min(max(eyeTargetY, 0), 1)
            )
            return FusionResult(position: currentPosition, isTeleport: true)
        }

        // Head refinement
        switch state {
        case .idle:
            // Before first saccade, head alone drives cursor
            currentPosition = GazePoint(
                x: min(max(0.5 + headDelta.dx, 0), 1),
                y: min(max(0.5 + headDelta.dy, 0), 1)
            )
        case .saccade:
            state = .refining
            fallthrough
        case .refining:
            // After saccade: head refines from the saccade landing point
            currentPosition = GazePoint(
                x: min(max(currentPosition.x + headDelta.dx * 0.3, 0), 1),
                y: min(max(currentPosition.y + headDelta.dy * 0.3, 0), 1)
            )
        }

        return FusionResult(position: currentPosition, isTeleport: false)
    }

    public func reset() {
        state = .idle
        currentPosition = GazePoint(x: 0.5, y: 0.5)
        saccadeDetector.reset()
        headTracker.reset()
    }
}
