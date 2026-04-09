import Foundation
import CoreGraphics
import CoreImage

public final class FrameProcessor: @unchecked Sendable {
    public struct FrameResult: Sendable {
        public let rawGaze: GazePoint
        public let leftEAR: Double
        public let rightEAR: Double
        public let faceDetected: Bool
        public let confidence: Float
        public let timestamp: Double
    }

    private let landmarkDetector = FaceLandmarkDetector()
    private let gazeEstimator: any GazeEstimating

    public init(gazeEstimator: any GazeEstimating) {
        self.gazeEstimator = gazeEstimator
    }

    public func process(pixelBuffer: CVPixelBuffer, timestamp: Double) -> FrameResult? {
        guard let face = landmarkDetector.detect(in: pixelBuffer) else { return nil }
        let gaze = gazeEstimator.estimate(faceBounds: face.faceBounds, leftPupil: face.leftPupil, rightPupil: face.rightPupil)
        let leftEAR = BlinkDetector.computeEAR(eyePoints: face.leftEyePoints)
        let rightEAR = BlinkDetector.computeEAR(eyePoints: face.rightEyePoints)
        return FrameResult(rawGaze: gaze, leftEAR: leftEAR, rightEAR: rightEAR, faceDetected: true, confidence: face.confidence, timestamp: timestamp)
    }
}
