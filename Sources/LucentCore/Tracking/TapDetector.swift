import Foundation
import CoreGraphics

// MARK: - Configuration

public struct TapConfig: Sendable {
    public var tapThreshold: Double
    public var returnThreshold: Double
    public var maxTapDuration: Double
    public var tapCooldown: Double
    public var baselineWindowSize: Int
    public var minimumConfidence: Float

    public init(
        tapThreshold: Double = 0.04,
        returnThreshold: Double = 0.02,
        maxTapDuration: Double = 0.4,
        tapCooldown: Double = 0.15,
        baselineWindowSize: Int = 10,
        minimumConfidence: Float = 0.5
    ) {
        self.tapThreshold = tapThreshold
        self.returnThreshold = returnThreshold
        self.maxTapDuration = maxTapDuration
        self.tapCooldown = tapCooldown
        self.baselineWindowSize = baselineWindowSize
        self.minimumConfidence = minimumConfidence
    }

    public static let defaults = TapConfig()
}

// MARK: - Tap Event

public struct TapEvent: Sendable, Equatable {
    public let fingertipPosition: CGPoint
    public let timestamp: Double

    public init(fingertipPosition: CGPoint, timestamp: Double) {
        self.fingertipPosition = fingertipPosition
        self.timestamp = timestamp
    }
}

// MARK: - TapDetector

public final class TapDetector: @unchecked Sendable {

    public var config: TapConfig

    private enum TapPhase {
        case idle
        case down(startTime: Double, startY: Double)
    }

    private var phase: TapPhase = .idle
    private var baselineYValues: [Double] = []
    private var lastTapTimestamp: Double = -1.0
    private var lastHandTimestamp: Double = -1.0

    public init(config: TapConfig = .defaults) {
        self.config = config
    }

    public func reset() {
        phase = .idle
        baselineYValues = []
        lastTapTimestamp = -1.0
        lastHandTimestamp = -1.0
    }

    /// Process a hand data frame. Returns a TapEvent if a complete tap is detected.
    public func update(handData: HandData) -> TapEvent? {
        // Reject low confidence
        guard handData.confidence >= config.minimumConfidence else { return nil }

        // Check for hand loss (>500ms gap) -- reset baseline
        if lastHandTimestamp >= 0 && (handData.timestamp - lastHandTimestamp) > 0.5 {
            reset()
        }
        lastHandTimestamp = handData.timestamp

        // Get index fingertip Y
        guard let indexTip = handData.landmarks[.indexTip] else { return nil }
        let tipY = Double(indexTip.y)

        // Compute baseline
        let baseline = computeBaseline()

        switch phase {
        case .idle:
            // Collect baseline samples when idle
            if baselineYValues.count < config.baselineWindowSize {
                baselineYValues.append(tipY)
                return nil
            }

            // Check cooldown
            if lastTapTimestamp >= 0 && (handData.timestamp - lastTapTimestamp) < config.tapCooldown {
                updateBaseline(tipY)
                return nil
            }

            // Check for tap-down: fingertip drops below baseline by threshold
            // In screen coordinates (top-left origin), downward motion = increasing Y
            if let bl = baseline, (tipY - bl) > config.tapThreshold {
                phase = .down(startTime: handData.timestamp, startY: tipY)
                return nil
            }

            // Update rolling baseline only when not tapping
            updateBaseline(tipY)
            return nil

        case .down(let startTime, _):
            guard let bl = baseline else {
                phase = .idle
                return nil
            }

            // Check if tap took too long
            if (handData.timestamp - startTime) > config.maxTapDuration {
                phase = .idle
                updateBaseline(tipY)
                return nil
            }

            // Check for tap-up: fingertip returns near baseline
            if abs(tipY - bl) <= config.returnThreshold {
                phase = .idle
                updateBaseline(tipY)
                // Enforce cooldown even during up-phase
                if lastTapTimestamp >= 0 && (handData.timestamp - lastTapTimestamp) < config.tapCooldown {
                    return nil
                }
                lastTapTimestamp = handData.timestamp
                return TapEvent(
                    fingertipPosition: indexTip,
                    timestamp: handData.timestamp
                )
            }

            return nil
        }
    }

    // MARK: - Private

    private func computeBaseline() -> Double? {
        guard baselineYValues.count >= config.baselineWindowSize else { return nil }
        return baselineYValues.suffix(config.baselineWindowSize).reduce(0.0, +) / Double(config.baselineWindowSize)
    }

    private func updateBaseline(_ y: Double) {
        baselineYValues.append(y)
        // Keep only the last N*2 values to prevent unbounded growth
        let maxSize = config.baselineWindowSize * 2
        if baselineYValues.count > maxSize {
            baselineYValues = Array(baselineYValues.suffix(maxSize))
        }
    }
}
