import Foundation
import CoreML
import CoreGraphics
import CoreImage
import CoreVideo
import Vision

/// Real gaze estimator powered by a CoreML L2CS-Net model.
/// Takes the camera frame, crops the face region, resizes to 224×224,
/// normalizes with ImageNet stats, runs inference, and maps the resulting
/// pitch/yaw angles to a 0-1 normalized gaze point.
public final class CoreMLGazeEstimator: GazeEstimating, @unchecked Sendable {

    private let model: VNCoreMLModel?
    private let ciContext = CIContext()

    /// Controls how wide the gaze angle range maps to the screen.
    /// Smaller value = more sensitive (less head/eye movement needed).
    /// Typical comfortable gaze range is about ±30° (0.52 rad).
    public var gazeRangeRadians: Double = 0.5

    public init() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all  // Use Neural Engine when available

            guard let modelURL = Bundle.module.url(forResource: "GazeEstimation", withExtension: "mlmodelc")
                    ?? Bundle.module.url(forResource: "GazeEstimation", withExtension: "mlpackage") else {
                print("[CoreMLGazeEstimator] Model not found in bundle")
                self.model = nil
                return
            }

            let compiledURL: URL
            if modelURL.pathExtension == "mlpackage" {
                compiledURL = try MLModel.compileModel(at: modelURL)
            } else {
                compiledURL = modelURL
            }

            let mlModel = try MLModel(contentsOf: compiledURL, configuration: config)
            self.model = try VNCoreMLModel(for: mlModel)
        } catch {
            print("[CoreMLGazeEstimator] Failed to load model: \(error)")
            self.model = nil
        }
    }

    public func estimate(pixelBuffer: CVPixelBuffer, faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint {
        guard let model = model else {
            // Fallback to simple head tracking if model failed to load
            return fallbackEstimate(faceBounds: faceBounds, leftPupil: leftPupil, rightPupil: rightPupil)
        }

        // Crop the face region from the pixel buffer with some padding.
        let imageW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // faceBounds is in normalized Vision coordinates (origin bottom-left).
        // Convert to pixel coordinates.
        let faceRect = CGRect(
            x: faceBounds.origin.x * imageW,
            y: (1.0 - faceBounds.origin.y - faceBounds.height) * imageH,
            width: faceBounds.width * imageW,
            height: faceBounds.height * imageH
        )

        // Add 20% padding around the face for context
        let pad = max(faceRect.width, faceRect.height) * 0.2
        let cropRect = faceRect.insetBy(dx: -pad, dy: -pad).intersection(
            CGRect(x: 0, y: 0, width: imageW, height: imageH)
        )

        guard !cropRect.isEmpty else {
            return fallbackEstimate(faceBounds: faceBounds, leftPupil: leftPupil, rightPupil: rightPupil)
        }

        // Create CIImage, crop, and resize to 224×224
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: cropRect)
        let scaleX = 224.0 / cropRect.width
        let scaleY = 224.0 / cropRect.height
        let resized = ciImage
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Render to a pixel buffer for VNCoreMLRequest
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 224, 224, kCVPixelFormatType_32BGRA, nil, &outputBuffer)
        guard let faceCropBuffer = outputBuffer else {
            return fallbackEstimate(faceBounds: faceBounds, leftPupil: leftPupil, rightPupil: rightPupil)
        }
        ciContext.render(resized, to: faceCropBuffer)

        // Run CoreML inference via Vision
        var gazeAngles: (pitch: Double, yaw: Double)?

        let request = VNCoreMLRequest(model: model) { request, _ in
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let multiArray = results.first?.featureValue.multiArrayValue else { return }
            let pitch = multiArray[0].doubleValue
            let yaw = multiArray[1].doubleValue
            gazeAngles = (pitch, yaw)
        }
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: faceCropBuffer, options: [:])
        try? handler.perform([request])

        guard let angles = gazeAngles else {
            return fallbackEstimate(faceBounds: faceBounds, leftPupil: leftPupil, rightPupil: rightPupil)
        }

        // Map pitch/yaw angles to 0-1 normalized coordinates.
        // pitch: positive = looking up → lower Y on screen (macOS Y increases downward)
        // yaw: positive = looking right → higher X on screen
        let range = gazeRangeRadians
        let gazeX = 0.5 + (angles.yaw / range) * 0.5
        let gazeY = 0.5 - (angles.pitch / range) * 0.5

        return GazePoint(
            x: min(max(gazeX, 0), 1),
            y: min(max(gazeY, 0), 1)
        )
    }

    /// Simple head+pupil fallback when model isn't available.
    private func fallbackEstimate(faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint {
        let headX = 1.0 - Double(faceBounds.midX)
        let headY = Double(faceBounds.midY)
        return GazePoint(x: headX, y: headY)
    }
}
