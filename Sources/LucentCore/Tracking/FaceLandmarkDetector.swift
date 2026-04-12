import Foundation
import Vision
import CoreGraphics

public struct FaceData: Sendable {
    public let faceBounds: CGRect
    public let leftEyePoints: [CGPoint]
    public let rightEyePoints: [CGPoint]
    public let leftPupil: CGPoint
    public let rightPupil: CGPoint
    public let outerLipsPoints: [CGPoint]
    public let innerLipsPoints: [CGPoint]
    public let leftBrowPoints: [CGPoint]
    public let rightBrowPoints: [CGPoint]
    public let confidence: Float
}

public final class FaceLandmarkDetector: @unchecked Sendable {
    /// Reason for last detection failure — helps diagnose camera/Vision issues.
    public private(set) var lastFailureReason: String?

    public init() {}

    public func detect(in pixelBuffer: CVPixelBuffer) -> FaceData? {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try handler.perform([request])
        } catch {
            lastFailureReason = "Vision error: \(error.localizedDescription)"
            return nil
        }

        guard let face = request.results?.first else {
            lastFailureReason = "No face found (results: \(request.results?.count ?? 0))"
            return nil
        }
        guard let landmarks = face.landmarks else {
            lastFailureReason = "Face found but no landmarks (confidence: \(face.confidence))"
            return nil
        }
        guard let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye,
              let leftPupil = landmarks.leftPupil, let rightPupil = landmarks.rightPupil else { return nil }

        let outerLips = landmarks.outerLips
        let innerLips = landmarks.innerLips
        let leftBrow = landmarks.leftEyebrow
        let rightBrow = landmarks.rightEyebrow

        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        let size = CGSize(width: imageWidth, height: imageHeight)
        let bounds = face.boundingBox

        func convertPoints(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
            let rawPoints = region.pointsInImage(imageSize: size)
            return (0..<region.pointCount).map { i in
                let p = rawPoints[i]
                return CGPoint(x: p.x / CGFloat(imageWidth), y: 1.0 - p.y / CGFloat(imageHeight))
            }
        }

        func convertSinglePoint(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
            convertPoints(region).first ?? .zero
        }

        return FaceData(
            faceBounds: CGRect(x: bounds.origin.x, y: 1.0 - bounds.origin.y - bounds.height, width: bounds.width, height: bounds.height),
            leftEyePoints: convertPoints(leftEye),
            rightEyePoints: convertPoints(rightEye),
            leftPupil: convertSinglePoint(leftPupil),
            rightPupil: convertSinglePoint(rightPupil),
            outerLipsPoints: outerLips.map { convertPoints($0) } ?? [],
            innerLipsPoints: innerLips.map { convertPoints($0) } ?? [],
            leftBrowPoints: leftBrow.map { convertPoints($0) } ?? [],
            rightBrowPoints: rightBrow.map { convertPoints($0) } ?? [],
            confidence: face.confidence
        )
    }
}
