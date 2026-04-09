import Foundation
import Vision
import CoreGraphics

/// Tracks hand pose from VNDetectHumanHandPoseRequest results.
/// Computes finger states from joint angles and tracks wrist velocity between frames.
public final class HandDetector: @unchecked Sendable {

    // MARK: - Configuration

    public var config: GestureConfig

    // MARK: - State

    private var previousWristPosition: CGPoint?
    private var previousTimestamp: Double?

    // MARK: - Output

    public struct ProcessedHand: Sendable {
        public let handData: HandData
        public let velocity: CGPoint
    }

    // MARK: - Init

    public init(config: GestureConfig = .defaults) {
        self.config = config
    }

    // MARK: - Reset

    public func reset() {
        previousWristPosition = nil
        previousTimestamp = nil
    }

    // MARK: - Vision Detection

    /// Run VNDetectHumanHandPoseRequest on a pixel buffer and return detected hands.
    public func detect(in pixelBuffer: CVPixelBuffer, timestamp: Double) -> [HandData] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)

        return observations.compactMap { observation in
            parseObservation(observation, imageWidth: imageWidth, imageHeight: imageHeight, timestamp: timestamp)
        }
    }

    // MARK: - Process a HandData (for wrist velocity tracking)

    /// Process a HandData to compute velocity. Call once per frame per hand.
    public func processHandObservation(_ handData: HandData) -> ProcessedHand {
        let velocity: CGPoint
        if let prevWrist = previousWristPosition {
            velocity = CGPoint(
                x: handData.wristPosition.x - prevWrist.x,
                y: handData.wristPosition.y - prevWrist.y
            )
        } else {
            velocity = .zero
        }

        previousWristPosition = handData.wristPosition
        previousTimestamp = handData.timestamp

        return ProcessedHand(handData: handData, velocity: velocity)
    }

    // MARK: - Observation Parsing

    private func parseObservation(
        _ observation: VNHumanHandPoseObservation,
        imageWidth: Int,
        imageHeight: Int,
        timestamp: Double
    ) -> HandData? {
        guard observation.confidence > 0.3 else { return nil }

        var landmarks: [HandJoint: CGPoint] = [:]

        let jointMapping: [(HandJoint, VNHumanHandPoseObservation.JointName)] = [
            (.wrist, .wrist),
            (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
            (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
            (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
            (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
            (.littleMCP, .littleMCP), (.littlePIP, .littlePIP), (.littleDIP, .littleDIP), (.littleTip, .littleTip),
        ]

        for (joint, visionJoint) in jointMapping {
            guard let point = try? observation.recognizedPoint(visionJoint),
                  point.confidence > 0.1 else { continue }
            // Vision coordinates: origin bottom-left, normalized 0..1
            // Convert to top-left origin to match face tracking convention
            landmarks[joint] = CGPoint(x: point.location.x, y: 1.0 - point.location.y)
        }

        guard landmarks[.wrist] != nil else { return nil }

        let fingerStates = classifyAllFingers(landmarks: landmarks)

        let chirality: Chirality = observation.chirality == .left ? .left : .right

        return HandData(
            landmarks: landmarks,
            fingerStates: fingerStates,
            wristPosition: landmarks[.wrist]!,
            chirality: chirality,
            confidence: observation.confidence,
            timestamp: timestamp
        )
    }

    // MARK: - Finger State Classification

    private func classifyAllFingers(landmarks: [HandJoint: CGPoint]) -> [Finger: FingerState] {
        var states: [Finger: FingerState] = [:]

        let fingerJoints: [(Finger, HandJoint, HandJoint, HandJoint)] = [
            (.thumb, .thumbCMC, .thumbMP, .thumbTip),
            (.index, .indexMCP, .indexPIP, .indexTip),
            (.middle, .middleMCP, .middlePIP, .middleTip),
            (.ring, .ringMCP, .ringPIP, .ringTip),
            (.little, .littleMCP, .littlePIP, .littleTip),
        ]

        for (finger, joint1, joint2, joint3) in fingerJoints {
            guard let a = landmarks[joint1],
                  let b = landmarks[joint2],
                  let c = landmarks[joint3] else {
                states[finger] = .curled
                continue
            }
            let angle = HandDetector.jointAngle(a: a, b: b, c: c)
            states[finger] = HandDetector.classifyFinger(finger, angle: angle, config: config)
        }

        return states
    }

    // MARK: - Public Static Helpers (exposed for testing)

    /// Compute the angle at point b formed by vectors (b -> a) and (b -> c), in degrees.
    public static func jointAngle(a: CGPoint, b: CGPoint, c: CGPoint) -> Double {
        let v1 = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)

        let dot = Double(v1.x * v2.x + v1.y * v2.y)
        let mag1 = sqrt(Double(v1.x * v1.x + v1.y * v1.y))
        let mag2 = sqrt(Double(v2.x * v2.x + v2.y * v2.y))

        guard mag1 > 0 && mag2 > 0 else { return 0 }

        let cosAngle = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return acos(cosAngle) * (180.0 / .pi)
    }

    /// Classify a finger as extended or curled based on the joint angle.
    /// Thumb uses a lower threshold (140 degrees) than other fingers (150 degrees).
    public static func classifyFinger(_ finger: Finger, angle: Double, config: GestureConfig) -> FingerState {
        let threshold = finger == .thumb ? config.thumbExtendedAngle : config.fingerExtendedAngle
        return angle >= threshold ? .extended : .curled
    }
}
