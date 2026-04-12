import Foundation
import CoreGraphics
import CoreVideo

/// Vision-landmark-based gaze estimator using pupil position relative to
/// eye corners for fine eye tracking, combined with face position for
/// coarse head tracking. Auto-centers to the user's neutral position.
public final class MockGazeEstimator: GazeEstimating, @unchecked Sendable {

    /// How much the eye signal is amplified. Higher = more eye-responsive.
    public var eyeGain: Double = 4.0

    /// Blend: 0 = pure head, 1 = pure eyes. 0.7 = mostly eyes.
    public var eyeWeight: Double = 0.7

    // Auto-centering
    private var centerX: Double = 0.5
    private var centerY: Double = 0.5
    private var framesSeen: Int = 0
    private let warmupFrames: Int = 45

    public init() {}

    public func estimate(pixelBuffer: CVPixelBuffer, faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint {
        // --- Head position (coarse) ---
        let headX = 1.0 - Double(faceBounds.midX)  // mirror for front camera
        let headY = Double(faceBounds.midY)

        // --- Eye position (fine) ---
        // Pupil midpoint relative to face bounding box gives eye direction.
        // When looking left: pupils shift left within the face box.
        // When looking right: pupils shift right.
        let pupilMidX = Double(leftPupil.x + rightPupil.x) / 2.0
        let pupilMidY = Double(leftPupil.y + rightPupil.y) / 2.0

        let faceMinX = Double(faceBounds.minX)
        let faceMinY = Double(faceBounds.minY)
        let faceW = max(Double(faceBounds.width), 0.001)
        let faceH = max(Double(faceBounds.height), 0.001)

        // 0-1 within the face bounding box
        let relX = (pupilMidX - faceMinX) / faceW
        let relY = (pupilMidY - faceMinY) / faceH

        // Offset from center of face, amplified
        let eyeOffX = (0.5 - relX) * eyeGain  // mirror: pupil left in image = looking right
        let eyeOffY = (relY - 0.5) * eyeGain

        // Combine: head anchor + eye offset
        let rawX = headX * (1.0 - eyeWeight) + (headX + eyeOffX * 0.15) * eyeWeight
        let rawY = headY * (1.0 - eyeWeight) + (headY + eyeOffY * 0.15) * eyeWeight

        // Auto-center: learn the user's neutral gaze over time
        framesSeen += 1
        let alpha: Double = framesSeen < warmupFrames ? 0.15 : 0.003
        centerX += alpha * (rawX - centerX)
        centerY += alpha * (rawY - centerY)

        // Map relative to center: deviation from neutral → screen position
        let gazeX = 0.5 + (rawX - centerX) * 3.0
        let gazeY = 0.5 + (rawY - centerY) * 3.0

        return GazePoint(
            x: min(max(gazeX, 0), 1),
            y: min(max(gazeY, 0), 1)
        )
    }
}
