// Sources/LucentCore/Camera/FrameProcessor.swift
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

    public func process(pixelBuffer: CVPixelBuffer, timestamp: Double) -> FrameResult? {
        guard let face = landmarkDetector.detect(in: pixelBuffer) else { return nil }

        let gaze = gazeEstimator.estimate(
            pixelBuffer: pixelBuffer,
            faceBounds: face.faceBounds,
            leftPupil: face.leftPupil,
            rightPupil: face.rightPupil
        )

        let leftEAR = BlinkDetector.computeEAR(eyePoints: face.leftEyePoints)
        let rightEAR = BlinkDetector.computeEAR(eyePoints: face.rightEyePoints)

        // Expression metrics
        let smile = ExpressionDetector.smileRatio(outerLipsPoints: face.outerLipsPoints)
        let mouthOpen = ExpressionDetector.mouthOpenRatio(innerLipsPoints: face.innerLipsPoints)

        let leftEyeTopY = face.leftEyePoints.map(\.y).min() ?? 0
        let rightEyeTopY = face.rightEyePoints.map(\.y).min() ?? 0
        let leftBrow = ExpressionDetector.browHeight(browPoints: face.leftBrowPoints, eyeTopY: leftEyeTopY)
        let rightBrow = ExpressionDetector.browHeight(browPoints: face.rightBrowPoints, eyeTopY: rightEyeTopY)
        let avgBrowHeight = (leftBrow + rightBrow) / 2.0

        let roll = ExpressionDetector.headRoll(leftPupil: face.leftPupil, rightPupil: face.rightPupil)

        let expressions = expressionDetector.update(
            leftEAR: leftEAR, rightEAR: rightEAR,
            smileRatio: smile, browHeight: avgBrowHeight,
            mouthOpenRatio: mouthOpen, headRoll: roll,
            timestamp: timestamp
        )

        // Hand detection + gesture recognition
        let detectedHands = handDetector.detect(in: pixelBuffer, timestamp: timestamp)
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
            leftEAR: leftEAR,
            rightEAR: rightEAR,
            faceDetected: true,
            confidence: face.confidence,
            timestamp: timestamp,
            expressions: expressions,
            headRoll: roll,
            smileRatio: smile,
            browHeight: avgBrowHeight,
            mouthOpenRatio: mouthOpen,
            hands: detectedHands,
            gestures: allGestures
        )
    }
}
