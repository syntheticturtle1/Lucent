import Foundation
import CoreGraphics
import CoreVideo

public protocol GazeEstimating: Sendable {
    func estimate(pixelBuffer: CVPixelBuffer, faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> FusionResult
}
