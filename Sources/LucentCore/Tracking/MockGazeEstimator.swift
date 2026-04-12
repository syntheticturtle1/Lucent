import Foundation
import CoreGraphics

/// Head-position gaze estimator that uses the face bounding box center
/// as a proxy for gaze direction. This gives rough head tracking:
/// turn your head right → cursor moves right, tilt down → cursor moves down.
///
/// Returns values in normalized 0-1 coordinates (fraction of camera frame).
/// X is mirrored so head-right maps to screen-right (front-facing cameras
/// produce mirrored images).
public final class MockGazeEstimator: GazeEstimating, @unchecked Sendable {
    public init() {}

    public func estimate(faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint {
        // Use face center — moves significantly with head turns, unlike pupils
        let faceX = Double(faceBounds.midX)
        let faceY = Double(faceBounds.midY)
        // Mirror X: front-facing camera is flipped, so invert so
        // turning your head right moves the cursor right on screen.
        return GazePoint(x: 1.0 - faceX, y: faceY)
    }
}
