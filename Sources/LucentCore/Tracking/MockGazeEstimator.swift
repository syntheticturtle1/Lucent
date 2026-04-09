import Foundation
import CoreGraphics

public final class MockGazeEstimator: GazeEstimating, @unchecked Sendable {
    public init() {}
    public func estimate(faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint {
        let gazeX = Double(leftPupil.x + rightPupil.x) / 2.0
        let gazeY = Double(leftPupil.y + rightPupil.y) / 2.0
        return GazePoint(x: gazeX, y: gazeY)
    }
}
