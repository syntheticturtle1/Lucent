// Tests/LucentCoreTests/ExpressionDetectorTests.swift
import Testing
import CoreGraphics
@testable import LucentCore

@Test func mouthAspectRatioOpenMouth() {
    let inner = makeRectPoints(cx: 0.5, cy: 0.5, width: 0.06, height: 0.04)
    let mar = ExpressionDetector.mouthOpenRatio(innerLipsPoints: inner)
    #expect(mar > 0.5)
}

@Test func mouthAspectRatioClosedMouth() {
    let inner = makeRectPoints(cx: 0.5, cy: 0.5, width: 0.06, height: 0.002)
    let mar = ExpressionDetector.mouthOpenRatio(innerLipsPoints: inner)
    #expect(mar < 0.1)
}

@Test func smileRatioWhenSmiling() {
    let outer = makeRectPoints(cx: 0.5, cy: 0.5, width: 0.1, height: 0.02)
    let ratio = ExpressionDetector.smileRatio(outerLipsPoints: outer)
    #expect(ratio > 3.0)
}

@Test func smileRatioNeutral() {
    let outer = makeRectPoints(cx: 0.5, cy: 0.5, width: 0.06, height: 0.03)
    let ratio = ExpressionDetector.smileRatio(outerLipsPoints: outer)
    #expect(ratio < 3.0)
}

@Test func browHeightRatioRaised() {
    let browPoints = [CGPoint(x: 0.4, y: 0.30), CGPoint(x: 0.45, y: 0.28),
                      CGPoint(x: 0.5, y: 0.27), CGPoint(x: 0.55, y: 0.28)]
    let eyeTop: CGFloat = 0.40
    let ratio = ExpressionDetector.browHeight(browPoints: browPoints, eyeTopY: eyeTop)
    #expect(ratio > 0.08)
}

@Test func browHeightRatioNeutral() {
    let browPoints = [CGPoint(x: 0.4, y: 0.38), CGPoint(x: 0.45, y: 0.37),
                      CGPoint(x: 0.5, y: 0.36), CGPoint(x: 0.55, y: 0.37)]
    let eyeTop: CGFloat = 0.40
    let ratio = ExpressionDetector.browHeight(browPoints: browPoints, eyeTopY: eyeTop)
    #expect(ratio < 0.05)
}

@Test func headRollAngleLevel() {
    let roll = ExpressionDetector.headRoll(leftPupil: CGPoint(x: 0.4, y: 0.5),
                                            rightPupil: CGPoint(x: 0.6, y: 0.5))
    #expect(abs(roll) < 1.0)
}

@Test func headRollAngleTilted() {
    let roll = ExpressionDetector.headRoll(leftPupil: CGPoint(x: 0.4, y: 0.5),
                                            rightPupil: CGPoint(x: 0.6, y: 0.45))
    #expect(roll > 5.0)
}

@Test func winkLeftDetected() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    var detected: [DetectedExpression] = []
    for i in 0..<10 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        detected += detector.update(leftEAR: 0.05, rightEAR: 0.3,
                                     smileRatio: 2.0, browHeight: 0.03,
                                     mouthOpenRatio: 0.05, headRoll: 0.0, timestamp: t)
    }
    #expect(detected.contains(where: { $0.type == .winkLeft }))
}

@Test func winkNotDetectedDuringBlink() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    var detected: [DetectedExpression] = []
    for i in 0..<10 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        detected += detector.update(leftEAR: 0.05, rightEAR: 0.05,
                                     smileRatio: 2.0, browHeight: 0.03,
                                     mouthOpenRatio: 0.05, headRoll: 0.0, timestamp: t)
    }
    #expect(!detected.contains(where: { $0.type == .winkLeft }))
    #expect(!detected.contains(where: { $0.type == .winkRight }))
}

@Test func smileDetectedAfterHold() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    var detected: [DetectedExpression] = []
    for i in 0..<20 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        detected += detector.update(leftEAR: 0.3, rightEAR: 0.3,
                                     smileRatio: 4.0, browHeight: 0.03,
                                     mouthOpenRatio: 0.05, headRoll: 0.0, timestamp: t)
    }
    #expect(detected.contains(where: { $0.type == .smile }))
}

@Test func browRaiseDetected() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    var detected: [DetectedExpression] = []
    for i in 0..<15 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        detected += detector.update(leftEAR: 0.3, rightEAR: 0.3,
                                     smileRatio: 2.0, browHeight: 0.10,
                                     mouthOpenRatio: 0.05, headRoll: 0.0, timestamp: t)
    }
    #expect(detected.contains(where: { $0.type == .browRaise }))
}

@Test func mouthOpenDetected() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    var detected: [DetectedExpression] = []
    for i in 0..<15 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        detected += detector.update(leftEAR: 0.3, rightEAR: 0.3,
                                     smileRatio: 2.0, browHeight: 0.03,
                                     mouthOpenRatio: 0.6, headRoll: 0.0, timestamp: t)
    }
    #expect(detected.contains(where: { $0.type == .mouthOpen }))
}

@Test func cooldownPreventsRapidRefire() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    var first: [DetectedExpression] = []
    for i in 0..<10 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        first += detector.update(leftEAR: 0.05, rightEAR: 0.3,
                                  smileRatio: 2.0, browHeight: 0.03,
                                  mouthOpenRatio: 0.05, headRoll: 0.0, timestamp: t)
    }
    #expect(first.contains(where: { $0.type == .winkLeft }))
    var second: [DetectedExpression] = []
    for i in 0..<5 {
        let t = 2.35 + Double(i) * (1.0/30.0)
        second += detector.update(leftEAR: 0.05, rightEAR: 0.3,
                                   smileRatio: 2.0, browHeight: 0.03,
                                   mouthOpenRatio: 0.05, headRoll: 0.0, timestamp: t)
    }
    #expect(!second.contains(where: { $0.type == .winkLeft }), "Should be in cooldown")
}

// MARK: - Helpers

private func feedNeutralFrames(detector: ExpressionDetector, count: Int) {
    for i in 0..<count {
        let t = Double(i) * (1.0/30.0)
        _ = detector.update(leftEAR: 0.3, rightEAR: 0.3,
                            smileRatio: 2.0, browHeight: 0.03,
                            mouthOpenRatio: 0.05, headRoll: 0.0, timestamp: t)
    }
}

private func makeRectPoints(cx: Double, cy: Double, width: Double, height: Double) -> [CGPoint] {
    let hw = width / 2, hh = height / 2
    return [
        CGPoint(x: cx + hw, y: cy),
        CGPoint(x: cx + hw * 0.7, y: cy - hh * 0.7),
        CGPoint(x: cx, y: cy - hh),
        CGPoint(x: cx - hw * 0.7, y: cy - hh * 0.7),
        CGPoint(x: cx - hw, y: cy),
        CGPoint(x: cx - hw * 0.7, y: cy + hh * 0.7),
        CGPoint(x: cx, y: cy + hh),
        CGPoint(x: cx + hw * 0.7, y: cy + hh * 0.7),
    ]
}
