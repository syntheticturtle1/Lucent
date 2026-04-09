import Foundation
import CoreGraphics

/// Detects facial expressions by computing geometric ratios from landmark data and
/// comparing them against a resting baseline calibrated from the first N frames.
public final class ExpressionDetector: @unchecked Sendable {

    // MARK: - Configuration

    /// Per-expression hold/cooldown/threshold configuration.
    public var configs: [ExpressionType: ExpressionConfig] = ExpressionConfig.defaults

    /// EAR value below which an eye is considered closed for wink detection.
    public var winkClosedThreshold: Double = 0.15

    /// EAR value above which an eye is considered open for wink detection.
    public var winkOpenThreshold: Double = 0.22

    /// Number of frames used to build the resting baseline.
    public var baselineFrames: Int = 60

    // MARK: - Baseline state

    private var frameCount: Int = 0
    private var baselineSmileSum: Double = 0
    private var baselineBrowSum: Double = 0
    private var baselineMouthSum: Double = 0

    private var baselineSmile: Double?
    private var baselineBrow: Double?
    private var baselineMouth: Double?

    // MARK: - Detection state

    /// When each expression's current activation started (nil = not currently active).
    private var activeExpressions: [ExpressionType: Double] = [:]

    /// The timestamp at which each expression last fired.
    private var lastFiredTime: [ExpressionType: Double] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Reset the baseline accumulator so calibration restarts from the next frame.
    public func resetBaseline() {
        frameCount = 0
        baselineSmileSum = 0
        baselineBrowSum = 0
        baselineMouthSum = 0
        baselineSmile = nil
        baselineBrow = nil
        baselineMouth = nil
        activeExpressions.removeAll()
        lastFiredTime.removeAll()
    }

    /// Feed one frame of computed metrics and receive any newly-triggered expressions.
    ///
    /// - Parameters:
    ///   - leftEAR: Eye Aspect Ratio for the left eye.
    ///   - rightEAR: Eye Aspect Ratio for the right eye.
    ///   - smileRatio: Width-to-height ratio of the outer lip bounding box.
    ///   - browHeight: Average distance of brow points above the eye top.
    ///   - mouthOpenRatio: Height-to-width ratio of the inner lip bounding box.
    ///   - headRoll: Head tilt angle in degrees.
    ///   - timestamp: Monotonically increasing time in seconds.
    /// - Returns: Any expressions detected and triggered in this frame.
    public func update(
        leftEAR: Double,
        rightEAR: Double,
        smileRatio: Double,
        browHeight: Double,
        mouthOpenRatio: Double,
        headRoll: Double,
        timestamp: Double
    ) -> [DetectedExpression] {

        // ── Phase 1: Accumulate baseline ──────────────────────────────────────
        if frameCount < baselineFrames {
            baselineSmileSum += smileRatio
            baselineBrowSum  += browHeight
            baselineMouthSum += mouthOpenRatio
            frameCount += 1

            if frameCount == baselineFrames {
                let n = Double(baselineFrames)
                baselineSmile = baselineSmileSum / n
                baselineBrow  = baselineBrowSum  / n
                baselineMouth = baselineMouthSum / n
            }
            return []
        }

        // ── Phase 2: Detection ────────────────────────────────────────────────
        var triggered: [DetectedExpression] = []

        // Wink detection uses fixed thresholds (no baseline).
        triggerWink(type: .winkLeft,
                    closedEAR: leftEAR, openEAR: rightEAR,
                    timestamp: timestamp, into: &triggered)
        triggerWink(type: .winkRight,
                    closedEAR: rightEAR, openEAR: leftEAR,
                    timestamp: timestamp, into: &triggered)

        // Baseline-relative expression detection.
        if let smile = baselineSmile {
            triggerExpression(type: .smile,
                              current: smileRatio,
                              baseline: smile,
                              timestamp: timestamp,
                              into: &triggered)
        }
        if let brow = baselineBrow {
            triggerExpression(type: .browRaise,
                              current: browHeight,
                              baseline: brow,
                              timestamp: timestamp,
                              into: &triggered)
        }
        if let mouth = baselineMouth {
            triggerExpression(type: .mouthOpen,
                              current: mouthOpenRatio,
                              baseline: mouth,
                              timestamp: timestamp,
                              into: &triggered)
        }

        return triggered
    }

    // MARK: - Static Geometric Helpers

    /// Height-to-width ratio of the bounding box of the inner lip points.
    /// High values indicate an open mouth.
    public static func mouthOpenRatio(innerLipsPoints: [CGPoint]) -> Double {
        guard !innerLipsPoints.isEmpty else { return 0 }
        let (minX, maxX, minY, maxY) = boundingBox(of: innerLipsPoints)
        let width  = Double(maxX - minX)
        let height = Double(maxY - minY)
        guard width > 0 else { return 0 }
        return height / width
    }

    /// Width-to-height ratio of the bounding box of the outer lip points.
    /// High values indicate a wide smile.
    public static func smileRatio(outerLipsPoints: [CGPoint]) -> Double {
        guard !outerLipsPoints.isEmpty else { return 0 }
        let (minX, maxX, minY, maxY) = boundingBox(of: outerLipsPoints)
        let width  = Double(maxX - minX)
        let height = Double(maxY - minY)
        guard height > 0 else { return 0 }
        return width / height
    }

    /// Average vertical distance from the brow points to the top of the eye.
    /// In image coordinates (Y increasing downward), brow Y < eyeTopY when raised.
    public static func browHeight(browPoints: [CGPoint], eyeTopY: CGFloat) -> Double {
        guard !browPoints.isEmpty else { return 0 }
        let avgBrowY = browPoints.reduce(0.0) { $0 + Double($1.y) } / Double(browPoints.count)
        return max(0, Double(eyeTopY) - avgBrowY)
    }

    /// Returns the head roll angle in degrees computed from the inter-pupil vector.
    /// Positive values indicate the head is tilted so the right pupil is higher than the left.
    public static func headRoll(leftPupil: CGPoint, rightPupil: CGPoint) -> Double {
        let dx = Double(rightPupil.x - leftPupil.x)
        let dy = Double(rightPupil.y - leftPupil.y)
        // Negate dy because image Y increases downward; we want geometric angle.
        let radians = atan2(-dy, dx)
        return radians * (180.0 / .pi)
    }

    // MARK: - Private Detection Helpers

    private func triggerWink(
        type: ExpressionType,
        closedEAR: Double,
        openEAR: Double,
        timestamp: Double,
        into result: inout [DetectedExpression]
    ) {
        let config = configs[type] ?? ExpressionConfig.defaults[type]!
        let isWinking = closedEAR < winkClosedThreshold && openEAR > winkOpenThreshold

        if isWinking {
            let lastFired = lastFiredTime[type] ?? -.infinity
            let cooldownCleared = timestamp - lastFired >= config.cooldown

            // Only start (or keep) the hold timer once the cooldown has expired.
            if cooldownCleared {
                if activeExpressions[type] == nil {
                    activeExpressions[type] = timestamp
                }
                let startTime = activeExpressions[type]!
                let held = timestamp - startTime

                if held >= config.holdDuration {
                    result.append(DetectedExpression(type: type,
                                                     confidence: 1.0,
                                                     timestamp: timestamp))
                    lastFiredTime[type] = timestamp
                    activeExpressions[type] = nil  // reset so hold must restart after next cooldown
                }
            } else {
                // Still in cooldown — keep resetting the hold start so it
                // only counts from when the cooldown actually clears.
                activeExpressions[type] = nil
            }
        } else {
            activeExpressions[type] = nil
        }
    }

    private func triggerExpression(
        type: ExpressionType,
        current: Double,
        baseline: Double,
        timestamp: Double,
        into result: inout [DetectedExpression]
    ) {
        let config = configs[type] ?? ExpressionConfig.defaults[type]!
        let threshold = baseline * config.thresholdMultiplier
        let isActive = current > threshold

        if isActive {
            let lastFired = lastFiredTime[type] ?? -.infinity
            let cooldownCleared = timestamp - lastFired >= config.cooldown

            // Only accumulate hold time once cooldown has expired.
            if cooldownCleared {
                if activeExpressions[type] == nil {
                    activeExpressions[type] = timestamp
                }
                let startTime = activeExpressions[type]!
                let held = timestamp - startTime

                if held >= config.holdDuration {
                    let confidence = min(1.0, (current - threshold) / threshold)
                    result.append(DetectedExpression(type: type,
                                                     confidence: confidence,
                                                     timestamp: timestamp))
                    lastFiredTime[type] = timestamp
                    activeExpressions[type] = nil  // reset so hold must restart after next cooldown
                }
            } else {
                // Still in cooldown — don't start accumulating hold time yet.
                activeExpressions[type] = nil
            }
        } else {
            activeExpressions[type] = nil
        }
    }

    // MARK: - Geometry Utilities

    private static func boundingBox(of points: [CGPoint]) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        for p in points.dropFirst() {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        return (minX, maxX, minY, maxY)
    }
}
