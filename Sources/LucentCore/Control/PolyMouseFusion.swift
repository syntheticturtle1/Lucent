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
/// A saccade is a fast jump in pupil-relative-to-face position.
public final class SaccadeDetector: @unchecked Sendable {
    /// Minimum pupil velocity (normalized units per frame) to trigger a saccade.
    public var threshold: Double = 0.08

    /// Cooldown frames after a saccade before detecting another.
    public var cooldownFrames: Int = 10

    private var previousRelX: Double?
    private var previousRelY: Double?
    private var cooldownCounter: Int = 0

    public init() {}

    public struct Result: Sendable {
        public let detected: Bool
        /// Where the eyes are looking (normalized 0-1 within face), only valid if detected.
        public let targetRelX: Double
        public let targetRelY: Double
    }

    /// Check if a saccade occurred this frame.
    /// - Parameters:
    ///   - relPupilX: Pupil X position within face bounding box (0-1).
    ///   - relPupilY: Pupil Y position within face bounding box (0-1).
    public func check(relPupilX: Double, relPupilY: Double) -> Result {
        defer {
            previousRelX = relPupilX
            previousRelY = relPupilY
            if cooldownCounter > 0 { cooldownCounter -= 1 }
        }

        guard let prevX = previousRelX, let prevY = previousRelY else {
            return Result(detected: false, targetRelX: relPupilX, targetRelY: relPupilY)
        }

        let dx = relPupilX - prevX
        let dy = relPupilY - prevY
        let velocity = (dx * dx + dy * dy).squareRoot()

        if velocity > threshold && cooldownCounter == 0 {
            cooldownCounter = cooldownFrames
            return Result(detected: true, targetRelX: relPupilX, targetRelY: relPupilY)
        }

        return Result(detected: false, targetRelX: relPupilX, targetRelY: relPupilY)
    }

    public func reset() {
        previousRelX = nil
        previousRelY = nil
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
