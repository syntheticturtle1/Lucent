import Foundation
import CoreML
import CoreGraphics
import CoreImage
import CoreVideo

/// Real gaze estimator powered by a CoreML L2CS-Net model.
/// Crops the face from the camera frame, normalizes with ImageNet stats,
/// runs inference, and maps pitch/yaw angles to screen coordinates.
public final class CoreMLGazeEstimator: GazeEstimating, @unchecked Sendable {

    private var mlModel: MLModel?
    private let ciContext = CIContext()

    /// ±gazeRangeRadians maps to the full screen width/height.
    /// Larger = less sensitive, more stable. 1.0 rad ≈ ±57°.
    public var gazeRangeRadians: Double = 1.0

    // ImageNet normalization constants
    private let mean: [Float] = [0.485, 0.456, 0.406]  // RGB
    private let std: [Float] = [0.229, 0.224, 0.225]

    public init() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all

            guard let modelURL = Bundle.module.url(forResource: "GazeEstimation", withExtension: "mlmodelc")
                    ?? Bundle.module.url(forResource: "GazeEstimation", withExtension: "mlpackage") else {
                print("[CoreMLGazeEstimator] Model not found in bundle")
                return
            }

            let compiledURL: URL
            if modelURL.pathExtension == "mlpackage" {
                compiledURL = try MLModel.compileModel(at: modelURL)
            } else {
                compiledURL = modelURL
            }

            mlModel = try MLModel(contentsOf: compiledURL, configuration: config)
            print("[CoreMLGazeEstimator] Model loaded successfully")
        } catch {
            print("[CoreMLGazeEstimator] Failed to load model: \(error)")
        }
    }

    public func estimate(pixelBuffer: CVPixelBuffer, faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint {
        guard let model = mlModel else {
            return fallbackEstimate(faceBounds: faceBounds)
        }

        // Crop face from pixel buffer
        let imageW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // faceBounds is normalized with origin bottom-left (Vision convention).
        let facePixelRect = CGRect(
            x: faceBounds.origin.x * imageW,
            y: (1.0 - faceBounds.origin.y - faceBounds.height) * imageH,
            width: faceBounds.width * imageW,
            height: faceBounds.height * imageH
        )

        // Pad 30% for context around the face
        let pad = max(facePixelRect.width, facePixelRect.height) * 0.3
        let cropRect = facePixelRect.insetBy(dx: -pad, dy: -pad).intersection(
            CGRect(x: 0, y: 0, width: imageW, height: imageH)
        )
        guard !cropRect.isEmpty, cropRect.width > 10, cropRect.height > 10 else {
            return fallbackEstimate(faceBounds: faceBounds)
        }

        // Render face crop to a 224×224 BGRA pixel buffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: cropRect)
        let translated = ciImage.transformed(by: CGAffineTransform(
            translationX: -cropRect.origin.x, y: -cropRect.origin.y))
        let scaleX = 224.0 / cropRect.width
        let scaleY = 224.0 / cropRect.height
        let resized = translated.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var faceBuf: CVPixelBuffer?
        CVPixelBufferCreate(nil, 224, 224, kCVPixelFormatType_32BGRA, nil, &faceBuf)
        guard let faceBuffer = faceBuf else { return fallbackEstimate(faceBounds: faceBounds) }
        ciContext.render(resized, to: faceBuffer)

        // Convert pixel buffer to ImageNet-normalized MLMultiArray [1, 3, 224, 224]
        guard let inputArray = pixelBufferToNormalizedArray(faceBuffer) else {
            return fallbackEstimate(faceBounds: faceBounds)
        }

        // Run inference
        do {
            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["face_crop": MLFeatureValue(multiArray: inputArray)]
            )
            let output = try model.prediction(from: inputFeatures)

            guard let gazeArray = output.featureValue(for: "gaze_angles")?.multiArrayValue else {
                return fallbackEstimate(faceBounds: faceBounds)
            }

            let pitch = gazeArray[0].doubleValue  // up/down
            let yaw = gazeArray[1].doubleValue    // left/right

            // Map angles to 0-1 screen coordinates
            let range = gazeRangeRadians
            let gazeX = 0.5 - (yaw / range) * 0.5    // negative yaw = looking right on screen
            let gazeY = 0.5 - (pitch / range) * 0.5   // negative pitch = looking down

            return GazePoint(
                x: min(max(gazeX, 0), 1),
                y: min(max(gazeY, 0), 1)
            )
        } catch {
            return fallbackEstimate(faceBounds: faceBounds)
        }
    }

    /// Convert a 224×224 BGRA pixel buffer to an ImageNet-normalized [1,3,224,224] MLMultiArray.
    private func pixelBufferToNormalizedArray(_ buffer: CVPixelBuffer) -> MLMultiArray? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        guard let array = try? MLMultiArray(shape: [1, 3, 224, 224], dataType: .float32) else {
            return nil
        }

        // BGRA → RGB, normalize with ImageNet mean/std
        for y in 0..<224 {
            for x in 0..<224 {
                let offset = y * bytesPerRow + x * 4
                let b = Float(ptr[offset]) / 255.0
                let g = Float(ptr[offset + 1]) / 255.0
                let r = Float(ptr[offset + 2]) / 255.0

                let idx_r = y * 224 + x              // channel 0
                let idx_g = 224 * 224 + y * 224 + x  // channel 1
                let idx_b = 2 * 224 * 224 + y * 224 + x  // channel 2

                array[idx_r] = NSNumber(value: (r - mean[0]) / std[0])
                array[idx_g] = NSNumber(value: (g - mean[1]) / std[1])
                array[idx_b] = NSNumber(value: (b - mean[2]) / std[2])
            }
        }

        return array
    }

    private func fallbackEstimate(faceBounds: CGRect) -> GazePoint {
        let headX = 1.0 - Double(faceBounds.midX)
        let headY = Double(faceBounds.midY)
        return GazePoint(x: headX, y: headY)
    }
}
