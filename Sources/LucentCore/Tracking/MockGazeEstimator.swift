import Foundation
import CoreGraphics
import CoreVideo

/// Hybrid head+eye gaze estimator using Apple Vision landmarks.
///
/// Two-level tracking:
/// 1. **Coarse** — face bounding box center positions the cursor in the
///    general screen region (turn head left → cursor moves left).
/// 2. **Fine** — pupil position *relative to the face* adjusts within that
///    region (look left with your eyes → cursor shifts left without moving
///    your head).
///
/// The eye component is amplified because pupil shifts within the face
/// are small (±0.1 in normalized coords) but represent significant gaze
/// direction changes.
public final class MockGazeEstimator: GazeEstimating, @unchecked Sendable {

    /// How much eye-within-face movement is amplified relative to head movement.
    /// Higher = more responsive to eye movement, less head turning needed.
    public var eyeGain: Double = 2.5

    /// Blend between head tracking (0.0) and eye tracking (1.0).
    /// Default 0.6 = 60% eye, 40% head. Gives responsive eyes with
    /// head as a coarse anchor.
    public var eyeWeight: Double = 0.6

    public init() {}

    public func estimate(pixelBuffer: CVPixelBuffer, faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint {
        // --- Coarse: head position ---
        // Face center in normalized image coordinates (0-1).
        // Mirror X so head-right → cursor-right (front-facing camera is flipped).
        let headX = 1.0 - Double(faceBounds.midX)
        let headY = Double(faceBounds.midY)

        // --- Fine: eye position relative to face ---
        // Pupil midpoint in image coords
        let pupilMidX = Double(leftPupil.x + rightPupil.x) / 2.0
        let pupilMidY = Double(leftPupil.y + rightPupil.y) / 2.0

        // Pupil position relative to the face bounding box (0-1 within the face)
        let faceW = max(Double(faceBounds.width), 0.001)
        let faceH = max(Double(faceBounds.height), 0.001)
        let relPupilX = (pupilMidX - Double(faceBounds.minX)) / faceW
        let relPupilY = (pupilMidY - Double(faceBounds.minY)) / faceH

        // Offset from face center (0 = looking straight, ±0.2 = looking to the side)
        // Mirror X for the same front-camera reason.
        let eyeOffsetX = (0.5 - relPupilX) * eyeGain
        let eyeOffsetY = (relPupilY - 0.5) * eyeGain

        // The eye component is an offset from the head position.
        // Normalize the eye position to 0-1 range by treating it as a
        // displacement around the head position.
        let eyeX = headX + eyeOffsetX * 0.3   // scale down so it doesn't overshoot
        let eyeY = headY + eyeOffsetY * 0.3

        // Blend head and eye
        let gazeX = headX * (1.0 - eyeWeight) + eyeX * eyeWeight
        let gazeY = headY * (1.0 - eyeWeight) + eyeY * eyeWeight

        // Clamp to 0-1
        return GazePoint(
            x: min(max(gazeX, 0), 1),
            y: min(max(gazeY, 0), 1)
        )
    }
}
