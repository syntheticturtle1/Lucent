import Testing
import CoreGraphics
@testable import LucentCore

// MARK: - Test Helpers

/// Create a minimal HandData with a specified index fingertip Y position.
private func makeHandData(indexTipY: CGFloat, timestamp: Double, confidence: Float = 0.9) -> HandData {
    var landmarks: [HandJoint: CGPoint] = [:]
    // Minimal landmarks: wrist and index tip
    landmarks[.wrist] = CGPoint(x: 0.5, y: 0.8)
    landmarks[.indexTip] = CGPoint(x: 0.5, y: indexTipY)
    landmarks[.indexMCP] = CGPoint(x: 0.5, y: 0.7)
    landmarks[.indexPIP] = CGPoint(x: 0.5, y: 0.65)
    landmarks[.indexDIP] = CGPoint(x: 0.5, y: 0.6)
    // Thumb and other fingers at rest
    landmarks[.thumbTip] = CGPoint(x: 0.4, y: 0.7)
    landmarks[.thumbCMC] = CGPoint(x: 0.45, y: 0.75)
    landmarks[.thumbMP] = CGPoint(x: 0.42, y: 0.72)
    landmarks[.thumbIP] = CGPoint(x: 0.41, y: 0.71)
    landmarks[.middleTip] = CGPoint(x: 0.55, y: 0.55)
    landmarks[.middleMCP] = CGPoint(x: 0.55, y: 0.7)
    landmarks[.middlePIP] = CGPoint(x: 0.55, y: 0.65)
    landmarks[.middleDIP] = CGPoint(x: 0.55, y: 0.6)
    landmarks[.ringTip] = CGPoint(x: 0.6, y: 0.58)
    landmarks[.ringMCP] = CGPoint(x: 0.6, y: 0.7)
    landmarks[.ringPIP] = CGPoint(x: 0.6, y: 0.65)
    landmarks[.ringDIP] = CGPoint(x: 0.6, y: 0.6)
    landmarks[.littleTip] = CGPoint(x: 0.65, y: 0.6)
    landmarks[.littleMCP] = CGPoint(x: 0.65, y: 0.7)
    landmarks[.littlePIP] = CGPoint(x: 0.65, y: 0.65)
    landmarks[.littleDIP] = CGPoint(x: 0.65, y: 0.62)

    let fingerStates: [Finger: FingerState] = [
        .thumb: .extended, .index: .extended, .middle: .extended,
        .ring: .extended, .little: .extended,
    ]
    return HandData(
        landmarks: landmarks,
        fingerStates: fingerStates,
        wristPosition: CGPoint(x: 0.5, y: 0.8),
        chirality: .right,
        confidence: confidence,
        timestamp: timestamp
    )
}

// MARK: - Tests

@Test func noTapDuringBaselineCollection() {
    let detector = TapDetector()
    // Feed a few frames at baseline Y -- should not fire
    for i in 0..<5 {
        let result = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
        #expect(result == nil, "Should not fire tap during baseline collection (frame \(i))")
    }
}

@Test func detectsSimpleTapDownAndUp() {
    let config = TapConfig(
        tapThreshold: 0.04,
        returnThreshold: 0.02,
        maxTapDuration: 0.4,
        tapCooldown: 0.15,
        baselineWindowSize: 5,
        minimumConfidence: 0.5
    )
    let detector = TapDetector(config: config)

    // Build baseline at Y=0.55 (5 frames)
    for i in 0..<5 {
        let _ = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
    }

    // Tap down: Y drops to 0.60 (0.05 below baseline of ~0.55, exceeds threshold of 0.04)
    let tapDown = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.20))
    #expect(tapDown == nil, "Tap-down alone should not fire event")

    // Tap up: Y returns to 0.55 (within returnThreshold of baseline)
    let tapUp = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.25))
    #expect(tapUp != nil, "Tap-up should fire tap event")
}

@Test func tapCooldownPreventsDoubleFire() {
    let config = TapConfig(
        tapThreshold: 0.04,
        returnThreshold: 0.02,
        maxTapDuration: 0.4,
        tapCooldown: 0.15,
        baselineWindowSize: 5,
        minimumConfidence: 0.5
    )
    let detector = TapDetector(config: config)

    // Build baseline
    for i in 0..<5 {
        let _ = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
    }

    // First tap
    let _ = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.20))
    let first = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.25))
    #expect(first != nil)

    // Immediate second tap (within cooldown of 0.15s)
    let _ = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.28))
    let second = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.33))
    #expect(second == nil, "Second tap within cooldown should not fire")

    // Third tap after cooldown expires (0.25 + 0.15 = 0.40)
    let _ = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.45))
    let third = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.50))
    #expect(third != nil, "Tap after cooldown should fire")
}

@Test func rejectsLowConfidenceHandData() {
    let detector = TapDetector()
    // Feed frames with confidence below minimum
    for i in 0..<10 {
        let result = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033, confidence: 0.2))
        #expect(result == nil)
    }
}

@Test func tapTooSlowIsRejected() {
    let config = TapConfig(
        tapThreshold: 0.04,
        returnThreshold: 0.02,
        maxTapDuration: 0.2,  // Very short window
        tapCooldown: 0.15,
        baselineWindowSize: 5,
        minimumConfidence: 0.5
    )
    let detector = TapDetector(config: config)

    // Build baseline
    for i in 0..<5 {
        let _ = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
    }

    // Tap down
    let _ = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.20))
    // Tap up too late (0.20 + 0.30 = 0.50, exceeds maxTapDuration of 0.2)
    let result = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.50))
    #expect(result == nil, "Tap exceeding maxTapDuration should not fire")
}

@Test func resetClearsState() {
    let detector = TapDetector()
    // Build some baseline
    for i in 0..<10 {
        let _ = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
    }
    detector.reset()
    // After reset, first frames should rebuild baseline (no tap)
    let result = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 1.0))
    #expect(result == nil, "Should not fire tap right after reset")
}

@Test func tapEventContainsFingertipPosition() {
    let config = TapConfig(
        tapThreshold: 0.04,
        returnThreshold: 0.02,
        maxTapDuration: 0.4,
        tapCooldown: 0.15,
        baselineWindowSize: 5,
        minimumConfidence: 0.5
    )
    let detector = TapDetector(config: config)

    // Build baseline
    for i in 0..<5 {
        let _ = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
    }

    // Tap
    let _ = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.20))
    let event = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.25))
    #expect(event != nil)
    #expect(event!.fingertipPosition.x == 0.5, "Fingertip X should match hand data")
}
