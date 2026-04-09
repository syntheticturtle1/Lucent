import Foundation
import CoreGraphics

public protocol GazeEstimating: Sendable {
    func estimate(faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint
}
