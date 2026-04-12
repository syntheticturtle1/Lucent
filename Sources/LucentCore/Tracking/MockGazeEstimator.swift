import Foundation
import CoreGraphics
import CoreVideo

/// PolyMouse-style gaze estimator: eyes for coarse jumps, head for fine aiming.
/// Uses Apple Vision face landmarks only — no external ML model needed.
public final class MockGazeEstimator: GazeEstimating, @unchecked Sendable {
    private let fusion = PolyMouseFusion()

    public init() {}

    public func estimate(pixelBuffer: CVPixelBuffer, faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> FusionResult {
        fusion.update(faceBounds: faceBounds, leftPupil: leftPupil, rightPupil: rightPupil)
    }
}
