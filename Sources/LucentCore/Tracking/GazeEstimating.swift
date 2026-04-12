import Foundation
import CoreGraphics
import CoreVideo

public protocol GazeEstimating: Sendable {
    /// Estimate gaze direction and return a normalized 0-1 gaze point.
    /// - Parameters:
    ///   - pixelBuffer: The raw camera frame (for CoreML face-crop models).
    ///   - faceBounds: Face bounding box in normalized image coordinates.
    ///   - leftPupil: Left pupil position in normalized image coordinates.
    ///   - rightPupil: Right pupil position in normalized image coordinates.
    func estimate(pixelBuffer: CVPixelBuffer, faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint
}
