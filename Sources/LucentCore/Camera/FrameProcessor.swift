// Sources/LucentCore/Camera/FrameProcessor.swift
import Foundation
import CoreGraphics
import CoreImage

public final class FrameProcessor: @unchecked Sendable {

    public struct FrameResult: Sendable {
        public let rawGaze: GazePoint
        public let isTeleport: Bool
        public let leftEAR: Double
        public let rightEAR: Double
        public let faceDetected: Bool
        public let confidence: Float
        public let timestamp: Double
        public let expressions: [DetectedExpression]
        public let headRoll: Double
        public let smileRatio: Double
        public let browHeight: Double
        public let mouthOpenRatio: Double
        public let hands: [HandData]
        public let gestures: [GestureEvent]
    }

    public let landmarkDetector = FaceLandmarkDetector()
    private let gazeEstimator: any GazeEstimating
    public let expressionDetector = ExpressionDetector()
    private let handDetector = HandDetector()
    public let gestureRecognizer = GestureRecognizer()

    public init(gazeEstimator: any GazeEstimating) {
        self.gazeEstimator = gazeEstimator
    }

    /// Process a camera frame. Returns a result even if only hands are
    /// detected (face can be nil). Returns nil only if NOTHING is detected.
    public func process(pixelBuffer: CVPixelBuffer, timestamp: Double) -> FrameResult? {
        // Run face and hand detection independently
        let face = landmarkDetector.detect(in: pixelBuffer)
        let detectedHands = handDetector.detect(in: pixelBuffer, timestamp: timestamp)

        // If neither face nor hands found, nothing to report
        if face == nil && detectedHands.isEmpty { return nil }

        // Face-dependent processing
        var gaze = GazePoint(x: 0.5, y: 0.5)
        var isTeleport = false
        var leftEAR: Double = 0.3
        var rightEAR: Double = 0.3
        var confidence: Float = 0
        var expressions: [DetectedExpression] = []
        var headRoll: Double = 0
        var smile: Double = 0
        var mouthOpen: Double = 0
        var avgBrowHeight: Double = 0

        if let face = face {
            let fusionResult = gazeEstimator.estimate(
                pixelBuffer: pixelBuffer,
                faceBounds: face.faceBounds,
                leftPupil: face.leftPupil,
                rightPupil: face.rightPupil
            )
            gaze = fusionResult.position
            isTeleport = fusionResult.isTeleport

            leftEAR = BlinkDetector.computeEAR(eyePoints: face.leftEyePoints)
            rightEAR = BlinkDetector.computeEAR(eyePoints: face.rightEyePoints)
            confidence = face.confidence

            smile = ExpressionDetector.smileRatio(outerLipsPoints: face.outerLipsPoints)
            mouthOpen = ExpressionDetector.mouthOpenRatio(innerLipsPoints: face.innerLipsPoints)

            let leftEyeTopY = face.leftEyePoints.map(\.y).min() ?? 0
            let rightEyeTopY = face.rightEyePoints.map(\.y).min() ?? 0
            let leftBrow = ExpressionDetector.browHeight(browPoints: face.leftBrowPoints, eyeTopY: leftEyeTopY)
            let rightBrow = ExpressionDetector.browHeight(browPoints: face.rightBrowPoints, eyeTopY: rightEyeTopY)
            avgBrowHeight = (leftBrow + rightBrow) / 2.0

            headRoll = ExpressionDetector.headRoll(leftPupil: face.leftPupil, rightPupil: face.rightPupil)

            expressions = expressionDetector.update(
                leftEAR: leftEAR, rightEAR: rightEAR,
                smileRatio: smile, browHeight: avgBrowHeight,
                mouthOpenRatio: mouthOpen, headRoll: headRoll,
                timestamp: timestamp
            )
        }

        // Hand gesture recognition (runs independently of face)
        var allGestures: [GestureEvent] = []
        if let primaryHand = detectedHands.first {
            let processed = handDetector.processHandObservation(primaryHand)
            allGestures = gestureRecognizer.update(
                hand: processed.handData,
                velocity: processed.velocity,
                timestamp: timestamp
            )
        } else {
            allGestures = gestureRecognizer.handleHandLost(timestamp: timestamp)
            handDetector.reset()
        }

        return FrameResult(
            rawGaze: gaze,
            isTeleport: isTeleport,
            leftEAR: leftEAR,
            rightEAR: rightEAR,
            faceDetected: face != nil,
            confidence: confidence,
            timestamp: timestamp,
            expressions: expressions,
            headRoll: headRoll,
            smileRatio: smile,
            browHeight: avgBrowHeight,
            mouthOpenRatio: mouthOpen,
            hands: detectedHands,
            gestures: allGestures
        )
    }
}
