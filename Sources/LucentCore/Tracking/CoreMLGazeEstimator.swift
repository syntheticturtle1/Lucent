import Foundation
import CoreML
import CoreGraphics
import CoreImage
import CoreVideo

/// Real gaze estimator powered by a CoreML L2CS-Net model.
/// Auto-centers to the user's natural gaze direction so "looking straight"
/// always maps to screen center regardless of camera angle or position.
public final class CoreMLGazeEstimator: GazeEstimating, @unchecked Sendable {

    private var mlModel: MLModel?
    private let ciContext = CIContext()

    /// How many radians of eye movement covers the full screen.
    /// Larger = less sensitive. 0.6 rad ≈ ±34° of gaze range.
    public var gazeRangeRadians: Double = 0.6

    // ImageNet normalization
    private let mean: [Float] = [0.485, 0.456, 0.406]
    private let std: [Float] = [0.229, 0.224, 0.225]

    // Auto-centering: running average of pitch/yaw to find "neutral" gaze
    private var centerPitch: Double = 0
    private var centerYaw: Double = 0
    private var framesSeen: Int = 0
    private let warmupFrames: Int = 30  // frames before centering stabilizes

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
        } catch {
            print("[CoreMLGazeEstimator] Failed: \(error)")
        }
    }

    public func estimate(pixelBuffer: CVPixelBuffer, faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint {
        guard let model = mlModel else {
            return fallbackEstimate(faceBounds: faceBounds)
        }

        let imageW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let facePixelRect = CGRect(
            x: faceBounds.origin.x * imageW,
            y: (1.0 - faceBounds.origin.y - faceBounds.height) * imageH,
            width: faceBounds.width * imageW,
            height: faceBounds.height * imageH
        )

        let pad = max(facePixelRect.width, facePixelRect.height) * 0.3
        let cropRect = facePixelRect.insetBy(dx: -pad, dy: -pad).intersection(
            CGRect(x: 0, y: 0, width: imageW, height: imageH)
        )
        guard !cropRect.isEmpty, cropRect.width > 10, cropRect.height > 10 else {
            return fallbackEstimate(faceBounds: faceBounds)
        }

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

        guard let inputArray = pixelBufferToNormalizedArray(faceBuffer) else {
            return fallbackEstimate(faceBounds: faceBounds)
        }

        do {
            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["face_crop": MLFeatureValue(multiArray: inputArray)]
            )
            let output = try model.prediction(from: inputFeatures)

            guard let gazeArray = output.featureValue(for: "gaze_angles")?.multiArrayValue else {
                return fallbackEstimate(faceBounds: faceBounds)
            }

            let rawPitch = gazeArray[0].doubleValue
            let rawYaw = gazeArray[1].doubleValue

            // Update auto-center with exponential moving average.
            // Fast adaptation during warmup, slow drift after.
            framesSeen += 1
            let alpha: Double = framesSeen < warmupFrames ? 0.3 : 0.005
            centerPitch += alpha * (rawPitch - centerPitch)
            centerYaw += alpha * (rawYaw - centerYaw)

            // Gaze relative to the user's neutral/center position.
            let relPitch = rawPitch - centerPitch
            let relYaw = rawYaw - centerYaw

            // Map to 0-1. Try both sign options — the correct mapping
            // depends on the camera's mirror state and the model's convention.
            // Front-facing camera: looking right in real life = face moves left in image
            let gazeX = 0.5 + (relYaw / gazeRangeRadians) * 0.5
            let gazeY = 0.5 + (relPitch / gazeRangeRadians) * 0.5

            return GazePoint(
                x: min(max(gazeX, 0), 1),
                y: min(max(gazeY, 0), 1)
            )
        } catch {
            return fallbackEstimate(faceBounds: faceBounds)
        }
    }

    /// Convert 224×224 BGRA pixel buffer to ImageNet-normalized [1,3,224,224].
    private func pixelBufferToNormalizedArray(_ buffer: CVPixelBuffer) -> MLMultiArray? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        guard let array = try? MLMultiArray(shape: [1, 3, 224, 224], dataType: .float32) else {
            return nil
        }

        let dataPtr = array.dataPointer.assumingMemoryBound(to: Float.self)
        let planeSize = 224 * 224

        for y in 0..<224 {
            for x in 0..<224 {
                let offset = y * bytesPerRow + x * 4
                let b = Float(ptr[offset]) / 255.0
                let g = Float(ptr[offset + 1]) / 255.0
                let r = Float(ptr[offset + 2]) / 255.0

                let idx = y * 224 + x
                dataPtr[idx] = (r - mean[0]) / std[0]              // R channel
                dataPtr[planeSize + idx] = (g - mean[1]) / std[1]  // G channel
                dataPtr[2 * planeSize + idx] = (b - mean[2]) / std[2]  // B channel
            }
        }

        return array
    }

    private func fallbackEstimate(faceBounds: CGRect) -> GazePoint {
        return GazePoint(x: 1.0 - Double(faceBounds.midX), y: Double(faceBounds.midY))
    }
}
