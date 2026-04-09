import Testing
import CoreGraphics
@testable import LucentCore

// MARK: - Joint Angle Computation Tests

@Test func jointAngleStraightFingerReturns180() {
    // Three collinear points: MCP at origin, PIP at (0, 0.1), TIP at (0, 0.2)
    let mcp = CGPoint(x: 0.5, y: 0.3)
    let pip = CGPoint(x: 0.5, y: 0.4)
    let tip = CGPoint(x: 0.5, y: 0.5)
    let angle = HandDetector.jointAngle(a: mcp, b: pip, c: tip)
    #expect(abs(angle - 180.0) < 1.0, "Straight finger should be ~180 degrees, got \(angle)")
}

@Test func jointAngleBentFingerReturns90() {
    // Right angle: MCP at (0.5, 0.3), PIP at (0.5, 0.4), TIP at (0.6, 0.4)
    let mcp = CGPoint(x: 0.5, y: 0.3)
    let pip = CGPoint(x: 0.5, y: 0.4)
    let tip = CGPoint(x: 0.6, y: 0.4)
    let angle = HandDetector.jointAngle(a: mcp, b: pip, c: tip)
    #expect(abs(angle - 90.0) < 1.0, "Right angle should be ~90 degrees, got \(angle)")
}

@Test func jointAngleFullyCurledReturnsSmallAngle() {
    // Finger curled back: MCP at (0.5, 0.3), PIP at (0.5, 0.4), TIP at (0.5, 0.35)
    let mcp = CGPoint(x: 0.5, y: 0.3)
    let pip = CGPoint(x: 0.5, y: 0.4)
    let tip = CGPoint(x: 0.5, y: 0.35)
    let angle = HandDetector.jointAngle(a: mcp, b: pip, c: tip)
    #expect(angle < 40.0, "Curled finger should have small angle, got \(angle)")
}

// MARK: - Finger State Classification Tests

@Test func fingerClassifiedAsExtendedWhenStraight() {
    let config = GestureConfig.defaults
    let state = HandDetector.classifyFinger(.index, angle: 160.0, config: config)
    #expect(state == .extended)
}

@Test func fingerClassifiedAsCurledWhenBent() {
    let config = GestureConfig.defaults
    let state = HandDetector.classifyFinger(.index, angle: 90.0, config: config)
    #expect(state == .curled)
}

@Test func thumbUsesLowerThreshold() {
    let config = GestureConfig.defaults
    // 145 degrees: above thumb threshold (140) but below finger threshold (150)
    let thumbState = HandDetector.classifyFinger(.thumb, angle: 145.0, config: config)
    let indexState = HandDetector.classifyFinger(.index, angle: 145.0, config: config)
    #expect(thumbState == .extended, "Thumb at 145 should be extended (threshold 140)")
    #expect(indexState == .curled, "Index at 145 should be curled (threshold 150)")
}

@Test func fingerAtExactThresholdIsExtended() {
    let config = GestureConfig.defaults
    let state = HandDetector.classifyFinger(.index, angle: 150.0, config: config)
    #expect(state == .extended, "Finger at exactly the threshold should be extended")
}

// MARK: - Wrist Velocity Tests

@Test func velocityComputedFromPreviousFrame() {
    let detector = HandDetector()
    let hand1 = makeHandData(
        wrist: CGPoint(x: 0.5, y: 0.5),
        allFingers: .extended,
        timestamp: 0.0
    )
    _ = detector.processHandObservation(hand1)

    let hand2 = makeHandData(
        wrist: CGPoint(x: 0.7, y: 0.5),
        allFingers: .extended,
        timestamp: 1.0 / 30.0
    )
    let result = detector.processHandObservation(hand2)
    #expect(result.velocity.x > 0.1, "Should detect rightward velocity")
    #expect(abs(result.velocity.y) < 0.01, "Should have no vertical velocity")
}

@Test func velocityIsZeroOnFirstFrame() {
    let detector = HandDetector()
    let hand = makeHandData(
        wrist: CGPoint(x: 0.5, y: 0.5),
        allFingers: .extended,
        timestamp: 0.0
    )
    let result = detector.processHandObservation(hand)
    #expect(abs(result.velocity.x) < 0.001)
    #expect(abs(result.velocity.y) < 0.001)
}

// MARK: - HandDetector.ProcessedHand Result Type

@Test func processedHandContainsFingerStates() {
    let detector = HandDetector()
    let hand = makeHandData(
        wrist: CGPoint(x: 0.5, y: 0.5),
        allFingers: .extended,
        timestamp: 0.0
    )
    let result = detector.processHandObservation(hand)
    #expect(result.handData.fingerStates.count == 5)
    for finger in Finger.allCases {
        #expect(result.handData.fingerStates[finger] == .extended)
    }
}

// MARK: - Test Helpers

private func makeHandData(
    wrist: CGPoint,
    allFingers fingerState: FingerState,
    timestamp: Double
) -> HandData {
    var landmarks: [HandJoint: CGPoint] = [:]
    landmarks[.wrist] = wrist

    // Generate synthetic landmark positions for each finger.
    // Extended fingers: joints go straight out from wrist.
    // Curled fingers: tip folds back toward wrist.
    let fingerBases: [(Finger, CGFloat)] = [
        (.thumb, -0.06), (.index, -0.03), (.middle, 0.0), (.ring, 0.03), (.little, 0.06)
    ]

    for (finger, xOffset) in fingerBases {
        let joints = jointsForFinger(finger)
        let baseX = wrist.x + xOffset
        let baseY = wrist.y

        if fingerState == .extended {
            // Straight finger going upward
            landmarks[joints.0] = CGPoint(x: baseX, y: baseY - 0.04)
            landmarks[joints.1] = CGPoint(x: baseX, y: baseY - 0.08)
            landmarks[joints.2] = CGPoint(x: baseX, y: baseY - 0.12)
            landmarks[joints.3] = CGPoint(x: baseX, y: baseY - 0.16)
        } else {
            // Curled finger: tip comes back toward palm
            landmarks[joints.0] = CGPoint(x: baseX, y: baseY - 0.04)
            landmarks[joints.1] = CGPoint(x: baseX, y: baseY - 0.06)
            landmarks[joints.2] = CGPoint(x: baseX, y: baseY - 0.04)
            landmarks[joints.3] = CGPoint(x: baseX, y: baseY - 0.02)
        }
    }

    // Compute finger states from the synthetic landmarks
    let config = GestureConfig.defaults
    var fingerStates: [Finger: FingerState] = [:]
    for finger in Finger.allCases {
        let joints = jointsForFinger(finger)
        let mcp = landmarks[joints.0]!
        let pip = landmarks[joints.1]!
        let tip = landmarks[joints.3]!
        let angle = HandDetector.jointAngle(a: mcp, b: pip, c: tip)
        fingerStates[finger] = HandDetector.classifyFinger(finger, angle: angle, config: config)
    }

    return HandData(
        landmarks: landmarks,
        fingerStates: fingerStates,
        wristPosition: wrist,
        chirality: .right,
        confidence: 0.9,
        timestamp: timestamp
    )
}

private func jointsForFinger(_ finger: Finger) -> (HandJoint, HandJoint, HandJoint, HandJoint) {
    switch finger {
    case .thumb:  return (.thumbCMC, .thumbMP, .thumbIP, .thumbTip)
    case .index:  return (.indexMCP, .indexPIP, .indexDIP, .indexTip)
    case .middle: return (.middleMCP, .middlePIP, .middleDIP, .middleTip)
    case .ring:   return (.ringMCP, .ringPIP, .ringDIP, .ringTip)
    case .little: return (.littleMCP, .littlePIP, .littleDIP, .littleTip)
    }
}
