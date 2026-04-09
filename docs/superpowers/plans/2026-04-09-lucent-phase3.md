# Phase 3: Hand Tracking + Gestures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable hand gesture recognition (swipe, pinch, fist, point, open palm) via Apple Vision hand pose detection, mapped to macOS actions (desktop switching, zoom, drag, precision cursor, pause), running simultaneously with existing eye/face tracking.
**Architecture:** HandDetector wraps VNDetectHumanHandPoseRequest and classifies finger states from joint angles. GestureRecognizer consumes HandData history to emit GestureEvents (one-shot swipes, continuous pinch/fist/point, toggle open palm). FrameProcessor runs hand detection alongside face detection on the same pixel buffer, and TrackingPipeline dispatches gesture events to InputController for OS actions.
**Tech Stack:** Apple Vision (VNDetectHumanHandPoseRequest), CoreGraphics event system, Swift Testing framework
---

### Task 1: GestureType Models
**Files:**
- Create: `Sources/LucentCore/Models/GestureType.swift`

- [ ] **Step 1: Create GestureType.swift with all hand tracking model types**

Create the file with all enums and structs needed by the hand tracking system.

```bash
# Verify the Models directory exists
ls Sources/LucentCore/Models/
```

Write `Sources/LucentCore/Models/GestureType.swift`:

```swift
import Foundation
import CoreGraphics

// MARK: - Hand Joint Topology

public enum HandJoint: String, CaseIterable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

// MARK: - Finger Classification

public enum Finger: String, CaseIterable, Sendable {
    case thumb, index, middle, ring, little
}

public enum FingerState: String, Sendable, Equatable {
    case extended
    case curled
}

public enum Chirality: String, Sendable, Equatable {
    case left
    case right
}

// MARK: - Hand Data (output of HandDetector)

public struct HandData: Sendable, Equatable {
    public let landmarks: [HandJoint: CGPoint]
    public let fingerStates: [Finger: FingerState]
    public let wristPosition: CGPoint
    public let chirality: Chirality
    public let confidence: Float
    public let timestamp: Double

    public init(
        landmarks: [HandJoint: CGPoint],
        fingerStates: [Finger: FingerState],
        wristPosition: CGPoint,
        chirality: Chirality,
        confidence: Float,
        timestamp: Double
    ) {
        self.landmarks = landmarks
        self.fingerStates = fingerStates
        self.wristPosition = wristPosition
        self.chirality = chirality
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

// MARK: - Movement

public enum SwipeDirection: String, Sendable, Equatable, CaseIterable {
    case left, right, up, down
}

public enum ZoomDirection: String, Sendable, Equatable {
    case zoomIn, zoomOut
}

// MARK: - Gesture Types

public enum GestureType: String, Codable, Sendable, CaseIterable, Equatable {
    case swipeLeft, swipeRight, swipeUp, swipeDown
    case pinch, fist, point, openPalm
}

public enum GestureState: Sendable, Equatable {
    case began
    case changed(value: Double)
    case ended
    case discrete
}

public struct GestureEvent: Sendable, Equatable {
    public let type: GestureType
    public let state: GestureState
    public let timestamp: Double

    public init(type: GestureType, state: GestureState, timestamp: Double) {
        self.type = type
        self.state = state
        self.timestamp = timestamp
    }
}

// MARK: - Gesture Configuration

public struct GestureConfig: Codable, Sendable {
    public var swipeDisplacementX: Double
    public var swipeDisplacementY: Double
    public var swipeWindowSeconds: Double
    public var swipeCooldownSeconds: Double
    public var pinchThreshold: Double
    public var fistHoldDuration: Double
    public var pointHoldDuration: Double
    public var openPalmHoldDuration: Double
    public var openPalmVelocityThreshold: Double
    public var fingerExtendedAngle: Double
    public var thumbExtendedAngle: Double

    public init(
        swipeDisplacementX: Double = 0.30,
        swipeDisplacementY: Double = 0.25,
        swipeWindowSeconds: Double = 0.5,
        swipeCooldownSeconds: Double = 0.5,
        pinchThreshold: Double = 0.03,
        fistHoldDuration: Double = 0.3,
        pointHoldDuration: Double = 0.2,
        openPalmHoldDuration: Double = 0.5,
        openPalmVelocityThreshold: Double = 0.01,
        fingerExtendedAngle: Double = 150.0,
        thumbExtendedAngle: Double = 140.0
    ) {
        self.swipeDisplacementX = swipeDisplacementX
        self.swipeDisplacementY = swipeDisplacementY
        self.swipeWindowSeconds = swipeWindowSeconds
        self.swipeCooldownSeconds = swipeCooldownSeconds
        self.pinchThreshold = pinchThreshold
        self.fistHoldDuration = fistHoldDuration
        self.pointHoldDuration = pointHoldDuration
        self.openPalmHoldDuration = openPalmHoldDuration
        self.openPalmVelocityThreshold = openPalmVelocityThreshold
        self.fingerExtendedAngle = fingerExtendedAngle
        self.thumbExtendedAngle = thumbExtendedAngle
    }

    public static let defaults = GestureConfig()
}
```

```bash
swift build 2>&1 | head -20
```

---

### Task 2: HandDetector (TDD -- Finger State Classification)
**Files:**
- Create: `Tests/LucentCoreTests/HandDetectorTests.swift`
- Create: `Sources/LucentCore/Tracking/HandDetector.swift`

- [ ] **Step 1: Write HandDetector tests first (red phase)**

Write `Tests/LucentCoreTests/HandDetectorTests.swift`:

```swift
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

struct ProcessedHandResult {
    let handData: HandData
    let velocity: CGPoint
}

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
```

```bash
swift test --filter HandDetector 2>&1 | tail -20
# Expected: compilation errors (HandDetector does not exist yet)
```

- [ ] **Step 2: Implement HandDetector (green phase)**

Write `Sources/LucentCore/Tracking/HandDetector.swift`:

```swift
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
```

```bash
swift test --filter HandDetector 2>&1 | tail -20
# Expected: all tests pass
```

---

### Task 3: GestureRecognizer (TDD -- Gesture Classification)
**Files:**
- Create: `Tests/LucentCoreTests/GestureRecognizerTests.swift`
- Create: `Sources/LucentCore/Tracking/GestureRecognizer.swift`

- [ ] **Step 1: Write GestureRecognizer tests first (red phase)**

Write `Tests/LucentCoreTests/GestureRecognizerTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import LucentCore

// MARK: - Swipe Detection Tests

@Test func swipeRightDetectedFromWristMovement() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // Simulate 15 frames (500ms at 30fps) of rightward wrist movement
    // Total displacement: 0.35 (above 0.30 threshold)
    for i in 0..<15 {
        let t = Double(i) * (1.0 / 30.0)
        let xPos = 0.3 + (0.35 * Double(i) / 14.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: xPos, y: 0.5),
            allFingers: .extended,
            timestamp: t
        )
        let velocity = CGPoint(x: 0.35 / 14.0, y: 0.0)
        events += recognizer.update(hand: hand, velocity: velocity, timestamp: t)
    }

    #expect(events.contains(where: { $0.type == .swipeRight && $0.state == .discrete }))
}

@Test func swipeLeftDetectedFromWristMovement() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    for i in 0..<15 {
        let t = Double(i) * (1.0 / 30.0)
        let xPos = 0.7 - (0.35 * Double(i) / 14.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: xPos, y: 0.5),
            allFingers: .extended,
            timestamp: t
        )
        let velocity = CGPoint(x: -0.35 / 14.0, y: 0.0)
        events += recognizer.update(hand: hand, velocity: velocity, timestamp: t)
    }

    #expect(events.contains(where: { $0.type == .swipeLeft && $0.state == .discrete }))
}

@Test func swipeUpDetectedFromWristMovement() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    for i in 0..<15 {
        let t = Double(i) * (1.0 / 30.0)
        let yPos = 0.7 - (0.30 * Double(i) / 14.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: 0.5, y: yPos),
            allFingers: .extended,
            timestamp: t
        )
        let velocity = CGPoint(x: 0.0, y: -0.30 / 14.0)
        events += recognizer.update(hand: hand, velocity: velocity, timestamp: t)
    }

    #expect(events.contains(where: { $0.type == .swipeUp && $0.state == .discrete }))
}

@Test func swipeDownDetectedFromWristMovement() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    for i in 0..<15 {
        let t = Double(i) * (1.0 / 30.0)
        let yPos = 0.3 + (0.30 * Double(i) / 14.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: 0.5, y: yPos),
            allFingers: .extended,
            timestamp: t
        )
        let velocity = CGPoint(x: 0.0, y: 0.30 / 14.0)
        events += recognizer.update(hand: hand, velocity: velocity, timestamp: t)
    }

    #expect(events.contains(where: { $0.type == .swipeDown && $0.state == .discrete }))
}

@Test func swipeNotDetectedWithCurledFingers() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // Same movement as swipeRight but with curled fingers
    for i in 0..<15 {
        let t = Double(i) * (1.0 / 30.0)
        let xPos = 0.3 + (0.35 * Double(i) / 14.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: xPos, y: 0.5),
            allFingers: .curled,
            timestamp: t
        )
        let velocity = CGPoint(x: 0.35 / 14.0, y: 0.0)
        events += recognizer.update(hand: hand, velocity: velocity, timestamp: t)
    }

    let swipes = events.filter {
        $0.type == .swipeRight || $0.type == .swipeLeft ||
        $0.type == .swipeUp || $0.type == .swipeDown
    }
    #expect(swipes.isEmpty, "Swipes require all fingers extended")
}

@Test func swipeCooldownPreventsRapidRefire() {
    let recognizer = GestureRecognizer()
    var firstSwipeEvents: [GestureEvent] = []
    var secondSwipeEvents: [GestureEvent] = []

    // First swipe
    for i in 0..<15 {
        let t = Double(i) * (1.0 / 30.0)
        let xPos = 0.3 + (0.35 * Double(i) / 14.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: xPos, y: 0.5),
            allFingers: .extended,
            timestamp: t
        )
        let velocity = CGPoint(x: 0.35 / 14.0, y: 0.0)
        firstSwipeEvents += recognizer.update(hand: hand, velocity: velocity, timestamp: t)
    }
    #expect(firstSwipeEvents.contains(where: { $0.type == .swipeRight }))

    // Second swipe immediately after (within cooldown)
    for i in 0..<15 {
        let t = 0.5 + Double(i) * (1.0 / 30.0)
        let xPos = 0.3 + (0.35 * Double(i) / 14.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: xPos, y: 0.5),
            allFingers: .extended,
            timestamp: t
        )
        let velocity = CGPoint(x: 0.35 / 14.0, y: 0.0)
        secondSwipeEvents += recognizer.update(hand: hand, velocity: velocity, timestamp: t)
    }
    #expect(!secondSwipeEvents.contains(where: { $0.type == .swipeRight }), "Should be in cooldown")
}

// MARK: - Fist Detection Tests

@Test func fistBeganAfterHoldDuration() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // 15 frames at 30fps = 500ms, fist hold is 300ms
    for i in 0..<15 {
        let t = Double(i) * (1.0 / 30.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: 0.5, y: 0.5),
            allFingers: .curled,
            timestamp: t
        )
        events += recognizer.update(hand: hand, velocity: .zero, timestamp: t)
    }

    #expect(events.contains(where: { $0.type == .fist && $0.state == .began }))
}

@Test func fistEndedWhenFingerExtends() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // Hold fist for 15 frames
    for i in 0..<15 {
        let t = Double(i) * (1.0 / 30.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: 0.5, y: 0.5),
            allFingers: .curled,
            timestamp: t
        )
        events += recognizer.update(hand: hand, velocity: .zero, timestamp: t)
    }

    // Release: open hand
    let releaseTime = 15.0 / 30.0
    let openHand = makeTestHandData(
        wrist: CGPoint(x: 0.5, y: 0.5),
        allFingers: .extended,
        timestamp: releaseTime
    )
    events += recognizer.update(hand: openHand, velocity: .zero, timestamp: releaseTime)

    #expect(events.contains(where: { $0.type == .fist && $0.state == .ended }))
}

@Test func fistNotTriggeredBeforeHoldDuration() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // Only 5 frames at 30fps = ~167ms (below 300ms threshold)
    for i in 0..<5 {
        let t = Double(i) * (1.0 / 30.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: 0.5, y: 0.5),
            allFingers: .curled,
            timestamp: t
        )
        events += recognizer.update(hand: hand, velocity: .zero, timestamp: t)
    }

    #expect(!events.contains(where: { $0.type == .fist && $0.state == .began }))
}

// MARK: - Point Detection Tests

@Test func pointBeganWhenIndexExtendedOthersCurled() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // 10 frames at 30fps = ~333ms (above 200ms threshold)
    for i in 0..<10 {
        let t = Double(i) * (1.0 / 30.0)
        let hand = makeTestHandDataWithFingerStates(
            wrist: CGPoint(x: 0.5, y: 0.5),
            thumb: .curled, index: .extended, middle: .curled, ring: .curled, little: .curled,
            timestamp: t
        )
        events += recognizer.update(hand: hand, velocity: .zero, timestamp: t)
    }

    #expect(events.contains(where: { $0.type == .point && $0.state == .began }))
}

@Test func pointReportsChangedWithFingertipPosition() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // Hold point for 15 frames to get both began and changed
    for i in 0..<15 {
        let t = Double(i) * (1.0 / 30.0)
        let hand = makeTestHandDataWithFingerStates(
            wrist: CGPoint(x: 0.5, y: 0.5),
            thumb: .curled, index: .extended, middle: .curled, ring: .curled, little: .curled,
            timestamp: t
        )
        events += recognizer.update(hand: hand, velocity: .zero, timestamp: t)
    }

    #expect(events.contains(where: {
        if case .changed = $0.state, $0.type == .point { return true }
        return false
    }))
}

// MARK: - Pinch Detection Tests

@Test func pinchBeganWhenThumbIndexClose() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    for i in 0..<5 {
        let t = Double(i) * (1.0 / 30.0)
        let hand = makePinchHandData(
            thumbTip: CGPoint(x: 0.50, y: 0.40),
            indexTip: CGPoint(x: 0.51, y: 0.40),
            timestamp: t
        )
        events += recognizer.update(hand: hand, velocity: .zero, timestamp: t)
    }

    #expect(events.contains(where: { $0.type == .pinch && $0.state == .began }))
}

@Test func pinchEndedWhenFingersSpread() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // Start pinch
    for i in 0..<5 {
        let t = Double(i) * (1.0 / 30.0)
        let hand = makePinchHandData(
            thumbTip: CGPoint(x: 0.50, y: 0.40),
            indexTip: CGPoint(x: 0.51, y: 0.40),
            timestamp: t
        )
        events += recognizer.update(hand: hand, velocity: .zero, timestamp: t)
    }

    // Release pinch - spread fingers apart
    let releaseTime = 5.0 / 30.0
    let hand = makePinchHandData(
        thumbTip: CGPoint(x: 0.40, y: 0.40),
        indexTip: CGPoint(x: 0.60, y: 0.40),
        timestamp: releaseTime
    )
    events += recognizer.update(hand: hand, velocity: .zero, timestamp: releaseTime)

    #expect(events.contains(where: { $0.type == .pinch && $0.state == .ended }))
}

// MARK: - Open Palm Detection Tests

@Test func openPalmTogglesAfterHoldDuration() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // Hold open palm stationary for 20 frames (667ms, above 500ms threshold)
    for i in 0..<20 {
        let t = Double(i) * (1.0 / 30.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: 0.5, y: 0.5),
            allFingers: .extended,
            timestamp: t
        )
        events += recognizer.update(hand: hand, velocity: .zero, timestamp: t)
    }

    #expect(events.contains(where: { $0.type == .openPalm && $0.state == .discrete }))
}

@Test func openPalmNotTriggeredWithMovement() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // Open palm with significant movement (should trigger swipe instead)
    for i in 0..<20 {
        let t = Double(i) * (1.0 / 30.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: 0.5, y: 0.5),
            allFingers: .extended,
            timestamp: t
        )
        let velocity = CGPoint(x: 0.05, y: 0.0) // above threshold
        events += recognizer.update(hand: hand, velocity: velocity, timestamp: t)
    }

    #expect(!events.contains(where: { $0.type == .openPalm }))
}

// MARK: - No Hand Resets State

@Test func noHandResetsActiveGestures() {
    let recognizer = GestureRecognizer()
    var events: [GestureEvent] = []

    // Start a fist
    for i in 0..<15 {
        let t = Double(i) * (1.0 / 30.0)
        let hand = makeTestHandData(
            wrist: CGPoint(x: 0.5, y: 0.5),
            allFingers: .curled,
            timestamp: t
        )
        events += recognizer.update(hand: hand, velocity: .zero, timestamp: t)
    }
    #expect(events.contains(where: { $0.type == .fist && $0.state == .began }))

    // Hand lost
    let lostTime = 15.0 / 30.0
    events += recognizer.handleHandLost(timestamp: lostTime)

    #expect(events.contains(where: { $0.type == .fist && $0.state == .ended }))
}

// MARK: - Test Helpers

private func makeTestHandData(
    wrist: CGPoint,
    allFingers fingerState: FingerState,
    timestamp: Double
) -> HandData {
    var fingerStates: [Finger: FingerState] = [:]
    for finger in Finger.allCases {
        fingerStates[finger] = fingerState
    }
    var landmarks: [HandJoint: CGPoint] = [:]
    landmarks[.wrist] = wrist
    // Place index tip for point gesture tests
    landmarks[.indexTip] = CGPoint(x: wrist.x, y: wrist.y - 0.15)
    landmarks[.thumbTip] = CGPoint(x: wrist.x - 0.05, y: wrist.y - 0.10)
    return HandData(
        landmarks: landmarks,
        fingerStates: fingerStates,
        wristPosition: wrist,
        chirality: .right,
        confidence: 0.9,
        timestamp: timestamp
    )
}

private func makeTestHandDataWithFingerStates(
    wrist: CGPoint,
    thumb: FingerState, index: FingerState, middle: FingerState,
    ring: FingerState, little: FingerState,
    timestamp: Double
) -> HandData {
    let fingerStates: [Finger: FingerState] = [
        .thumb: thumb, .index: index, .middle: middle, .ring: ring, .little: little
    ]
    var landmarks: [HandJoint: CGPoint] = [:]
    landmarks[.wrist] = wrist
    landmarks[.indexTip] = CGPoint(x: wrist.x, y: wrist.y - 0.15)
    landmarks[.thumbTip] = CGPoint(x: wrist.x - 0.05, y: wrist.y - 0.10)
    return HandData(
        landmarks: landmarks,
        fingerStates: fingerStates,
        wristPosition: wrist,
        chirality: .right,
        confidence: 0.9,
        timestamp: timestamp
    )
}

private func makePinchHandData(
    thumbTip: CGPoint,
    indexTip: CGPoint,
    timestamp: Double
) -> HandData {
    let distance = sqrt(
        pow(Double(thumbTip.x - indexTip.x), 2) +
        pow(Double(thumbTip.y - indexTip.y), 2)
    )
    let isPinching = distance < 0.03
    let fingerStates: [Finger: FingerState] = [
        .thumb: isPinching ? .curled : .extended,
        .index: isPinching ? .curled : .extended,
        .middle: .extended,
        .ring: .extended,
        .little: .extended,
    ]
    let wrist = CGPoint(x: (thumbTip.x + indexTip.x) / 2, y: 0.6)
    var landmarks: [HandJoint: CGPoint] = [:]
    landmarks[.wrist] = wrist
    landmarks[.thumbTip] = thumbTip
    landmarks[.indexTip] = indexTip
    return HandData(
        landmarks: landmarks,
        fingerStates: fingerStates,
        wristPosition: wrist,
        chirality: .right,
        confidence: 0.9,
        timestamp: timestamp
    )
}
```

```bash
swift test --filter GestureRecognizer 2>&1 | tail -20
# Expected: compilation errors (GestureRecognizer does not exist yet)
```

- [ ] **Step 2: Implement GestureRecognizer (green phase)**

Write `Sources/LucentCore/Tracking/GestureRecognizer.swift`:

```swift
import Foundation
import CoreGraphics

/// Recognizes gestures from a stream of HandData + velocity.
/// Emits GestureEvents for swipes, pinch, fist, point, and open palm.
public final class GestureRecognizer: @unchecked Sendable {

    // MARK: - Configuration

    public var config: GestureConfig

    // MARK: - Swipe State

    /// Sliding window of (wristPosition, timestamp) for swipe detection.
    private var wristHistory: [(position: CGPoint, timestamp: Double)] = []
    /// Tracks whether all fingers were extended throughout the swipe window.
    private var allFingersExtendedHistory: [Bool] = []
    /// Timestamp of last swipe fired (for cooldown).
    private var lastSwipeTime: Double = -.infinity

    // MARK: - Continuous Gesture State

    private var fistStartTime: Double?
    private var fistActive: Bool = false

    private var pointStartTime: Double?
    private var pointActive: Bool = false

    private var pinchActive: Bool = false
    private var previousPinchDistance: Double?

    private var openPalmStartTime: Double?
    private var openPalmFired: Bool = false

    // MARK: - Init

    public init(config: GestureConfig = .defaults) {
        self.config = config
    }

    // MARK: - Reset

    public func reset() {
        wristHistory.removeAll()
        allFingersExtendedHistory.removeAll()
        lastSwipeTime = -.infinity
        fistStartTime = nil
        fistActive = false
        pointStartTime = nil
        pointActive = false
        pinchActive = false
        previousPinchDistance = nil
        openPalmStartTime = nil
        openPalmFired = false
    }

    // MARK: - Main Update

    /// Process one frame of hand data. Returns any gesture events detected.
    public func update(hand: HandData, velocity: CGPoint, timestamp: Double) -> [GestureEvent] {
        var events: [GestureEvent] = []

        // Detect gestures in priority order
        events += detectPinch(hand: hand, timestamp: timestamp)
        events += detectFist(hand: hand, timestamp: timestamp)
        events += detectPoint(hand: hand, timestamp: timestamp)
        events += detectOpenPalm(hand: hand, velocity: velocity, timestamp: timestamp)
        events += detectSwipe(hand: hand, velocity: velocity, timestamp: timestamp)

        return events
    }

    // MARK: - Hand Lost

    /// Call when no hand is detected. Ends any active continuous gestures.
    public func handleHandLost(timestamp: Double) -> [GestureEvent] {
        var events: [GestureEvent] = []

        if fistActive {
            events.append(GestureEvent(type: .fist, state: .ended, timestamp: timestamp))
            fistActive = false
            fistStartTime = nil
        }
        if pointActive {
            events.append(GestureEvent(type: .point, state: .ended, timestamp: timestamp))
            pointActive = false
            pointStartTime = nil
        }
        if pinchActive {
            events.append(GestureEvent(type: .pinch, state: .ended, timestamp: timestamp))
            pinchActive = false
            previousPinchDistance = nil
        }

        wristHistory.removeAll()
        allFingersExtendedHistory.removeAll()
        openPalmStartTime = nil
        openPalmFired = false

        return events
    }

    // MARK: - Swipe Detection

    private func detectSwipe(hand: HandData, velocity: CGPoint, timestamp: Double) -> [GestureEvent] {
        let allExtended = Finger.allCases.allSatisfy { hand.fingerStates[$0] == .extended }

        // Add to history
        wristHistory.append((position: hand.wristPosition, timestamp: timestamp))
        allFingersExtendedHistory.append(allExtended)

        // Trim history to the swipe window
        let windowStart = timestamp - config.swipeWindowSeconds
        while let first = wristHistory.first, first.timestamp < windowStart {
            wristHistory.removeFirst()
            allFingersExtendedHistory.removeFirst()
        }

        // Check cooldown
        guard timestamp - lastSwipeTime >= config.swipeCooldownSeconds else { return [] }

        // Need at least 2 samples
        guard wristHistory.count >= 2 else { return [] }

        // All fingers must have been extended throughout the window
        guard allFingersExtendedHistory.allSatisfy({ $0 }) else { return [] }

        // Compute total displacement
        let first = wristHistory.first!.position
        let last = wristHistory.last!.position
        let dx = Double(last.x - first.x)
        let dy = Double(last.y - first.y)

        var gestureType: GestureType?

        if dx > Double(config.swipeDisplacementX) {
            gestureType = .swipeRight
        } else if dx < -Double(config.swipeDisplacementX) {
            gestureType = .swipeLeft
        } else if dy < -Double(config.swipeDisplacementY) {
            gestureType = .swipeUp
        } else if dy > Double(config.swipeDisplacementY) {
            gestureType = .swipeDown
        }

        if let type = gestureType {
            lastSwipeTime = timestamp
            wristHistory.removeAll()
            allFingersExtendedHistory.removeAll()
            return [GestureEvent(type: type, state: .discrete, timestamp: timestamp)]
        }

        return []
    }

    // MARK: - Pinch Detection

    private func detectPinch(hand: HandData, timestamp: Double) -> [GestureEvent] {
        guard let thumbTip = hand.landmarks[.thumbTip],
              let indexTip = hand.landmarks[.indexTip] else {
            if pinchActive {
                pinchActive = false
                previousPinchDistance = nil
                return [GestureEvent(type: .pinch, state: .ended, timestamp: timestamp)]
            }
            return []
        }

        let distance = sqrt(
            pow(Double(thumbTip.x - indexTip.x), 2) +
            pow(Double(thumbTip.y - indexTip.y), 2)
        )

        // Check that middle, ring, little are extended (pinch pose)
        let middleExtended = hand.fingerStates[.middle] == .extended
        let ringExtended = hand.fingerStates[.ring] == .extended
        let littleExtended = hand.fingerStates[.little] == .extended
        let isPinchPose = distance < config.pinchThreshold && middleExtended && ringExtended && littleExtended

        if isPinchPose {
            if !pinchActive {
                pinchActive = true
                previousPinchDistance = distance
                return [GestureEvent(type: .pinch, state: .began, timestamp: timestamp)]
            } else {
                let event = GestureEvent(type: .pinch, state: .changed(value: distance), timestamp: timestamp)
                previousPinchDistance = distance
                return [event]
            }
        } else {
            if pinchActive {
                pinchActive = false
                previousPinchDistance = nil
                return [GestureEvent(type: .pinch, state: .ended, timestamp: timestamp)]
            }
        }

        return []
    }

    // MARK: - Fist Detection

    private func detectFist(hand: HandData, timestamp: Double) -> [GestureEvent] {
        let allCurled = Finger.allCases.allSatisfy { hand.fingerStates[$0] == .curled }

        if allCurled {
            if fistStartTime == nil {
                fistStartTime = timestamp
            }
            let held = timestamp - fistStartTime!

            if held >= config.fistHoldDuration && !fistActive {
                fistActive = true
                return [GestureEvent(type: .fist, state: .began, timestamp: timestamp)]
            }
        } else {
            if fistActive {
                fistActive = false
                fistStartTime = nil
                return [GestureEvent(type: .fist, state: .ended, timestamp: timestamp)]
            }
            fistStartTime = nil
        }

        return []
    }

    // MARK: - Point Detection

    private func detectPoint(hand: HandData, timestamp: Double) -> [GestureEvent] {
        let indexExtended = hand.fingerStates[.index] == .extended
        let othersCurled = [Finger.thumb, .middle, .ring, .little].allSatisfy {
            hand.fingerStates[$0] == .curled
        }
        let isPointing = indexExtended && othersCurled

        if isPointing {
            if pointStartTime == nil {
                pointStartTime = timestamp
            }
            let held = timestamp - pointStartTime!

            if held >= config.pointHoldDuration {
                if !pointActive {
                    pointActive = true
                    return [GestureEvent(type: .point, state: .began, timestamp: timestamp)]
                } else {
                    // Report fingertip position as changed value
                    let indexTip = hand.landmarks[.indexTip] ?? hand.wristPosition
                    let positionValue = Double(indexTip.x) + Double(indexTip.y) * 10000.0
                    return [GestureEvent(type: .point, state: .changed(value: positionValue), timestamp: timestamp)]
                }
            }
        } else {
            if pointActive {
                pointActive = false
                pointStartTime = nil
                return [GestureEvent(type: .point, state: .ended, timestamp: timestamp)]
            }
            pointStartTime = nil
        }

        return []
    }

    // MARK: - Open Palm Detection

    private func detectOpenPalm(hand: HandData, velocity: CGPoint, timestamp: Double) -> [GestureEvent] {
        let allExtended = Finger.allCases.allSatisfy { hand.fingerStates[$0] == .extended }
        let speed = sqrt(Double(velocity.x * velocity.x + velocity.y * velocity.y))
        let isStationary = speed < config.openPalmVelocityThreshold

        if allExtended && isStationary {
            if openPalmStartTime == nil {
                openPalmStartTime = timestamp
            }
            let held = timestamp - openPalmStartTime!

            if held >= config.openPalmHoldDuration && !openPalmFired {
                openPalmFired = true
                return [GestureEvent(type: .openPalm, state: .discrete, timestamp: timestamp)]
            }
        } else {
            openPalmStartTime = nil
            openPalmFired = false
        }

        return []
    }
}
```

```bash
swift test --filter GestureRecognizer 2>&1 | tail -20
# Expected: all tests pass
```

---

### Task 4: InputController Additions
**Files:**
- Modify: `Sources/LucentCore/Control/InputController.swift`

- [ ] **Step 1: Add startDrag and endDrag methods**

Add to the end of `InputController`, before the closing `}`:

```swift
    // MARK: - Drag Operations

    /// Begin a click-and-drag at the given point (posts mouseDown).
    public func startDrag(at point: GazePoint) {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        if let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: cgPoint, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
        }
    }

    /// End a click-and-drag at the given point (posts mouseUp).
    public func endDrag(at point: GazePoint) {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        if let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: cgPoint, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }
    }

    /// Move the cursor during a drag (posts leftMouseDragged).
    public func dragMove(to point: GazePoint) {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        if let event = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDragged, mouseCursorPosition: cgPoint, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }
```

- [ ] **Step 2: Add desktop switching methods**

Add after the drag methods:

```swift
    // MARK: - Desktop Switching

    /// Switch desktop in the given direction using Ctrl+Arrow.
    public func switchDesktop(direction: SwipeDirection) {
        switch direction {
        case .left:  pressKey(keyCode: 0x7B, modifiers: .maskControl)  // Ctrl+Left
        case .right: pressKey(keyCode: 0x7C, modifiers: .maskControl)  // Ctrl+Right
        case .up:    break  // Handled by triggerMissionControl
        case .down:  break  // Handled by triggerExpose
        }
    }

    /// Trigger Mission Control (Ctrl+Up arrow).
    public func triggerMissionControl() {
        pressKey(keyCode: 0x7E, modifiers: .maskControl)
    }

    /// Trigger App Expose (Ctrl+Down arrow).
    public func triggerExpose() {
        pressKey(keyCode: 0x7D, modifiers: .maskControl)
    }
```

- [ ] **Step 3: Add zoom method**

Add after the desktop switching methods:

```swift
    // MARK: - Zoom

    /// Zoom in or out using Cmd+Plus or Cmd+Minus.
    public func zoom(direction: ZoomDirection) {
        switch direction {
        case .zoomIn:  pressKey(keyCode: 0x18, modifiers: .maskCommand)  // Cmd+= (plus)
        case .zoomOut: pressKey(keyCode: 0x1B, modifiers: .maskCommand)  // Cmd+- (minus)
        }
    }
```

```bash
swift build 2>&1 | head -20
```

---

### Task 5: FrameProcessor Update
**Files:**
- Modify: `Sources/LucentCore/Camera/FrameProcessor.swift`

- [ ] **Step 1: Add hand detection fields to FrameResult**

In `FrameProcessor.swift`, update the `FrameResult` struct to include hand and gesture data. Replace the existing `FrameResult` struct with:

```swift
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
```

- [ ] **Step 2: Add HandDetector and GestureRecognizer to FrameProcessor**

Add the new detector instances as private properties. Replace the properties section:

```swift
    private let landmarkDetector = FaceLandmarkDetector()
    private let gazeEstimator: any GazeEstimating
    private let expressionDetector = ExpressionDetector()
    private let handDetector = HandDetector()
    private let gestureRecognizer = GestureRecognizer()
```

- [ ] **Step 3: Update process() to run hand detection and gesture recognition**

Replace the entire `process(pixelBuffer:timestamp:)` method with:

```swift
    public func process(pixelBuffer: CVPixelBuffer, timestamp: Double) -> FrameResult? {
        guard let face = landmarkDetector.detect(in: pixelBuffer) else { return nil }

        let gaze = gazeEstimator.estimate(
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
```

```bash
swift build 2>&1 | head -20
```

---

### Task 6: TrackingPipeline Integration
**Files:**
- Modify: `App/TrackingPipeline.swift`

- [ ] **Step 1: Add hand gesture state properties**

Add the following published and private properties to `TrackingPipeline`, after the existing `@Published` properties:

```swift
    @Published public var handDetected: Bool = false
    @Published public var activeGesture: GestureType? = nil
    @Published public var handGesturesEnabled: Bool = true
    @Published public var handCount: Int = 0

    private var isDragging: Bool = false
    private var isPointActive: Bool = false
```

- [ ] **Step 2: Add gesture event handling method**

Add the following method in the `TrackingPipeline` extension (after `handleFaceLost`):

```swift
    private func handleGestureEvents(_ gestures: [GestureEvent], cursorPosition: GazePoint) {
        guard handGesturesEnabled else { return }

        for gesture in gestures {
            activeGesture = gesture.type

            switch gesture.type {
            case .swipeLeft:
                guard gesture.state == .discrete else { continue }
                inputController.switchDesktop(direction: .left)

            case .swipeRight:
                guard gesture.state == .discrete else { continue }
                inputController.switchDesktop(direction: .right)

            case .swipeUp:
                guard gesture.state == .discrete else { continue }
                inputController.triggerMissionControl()

            case .swipeDown:
                guard gesture.state == .discrete else { continue }
                inputController.triggerExpose()

            case .pinch:
                switch gesture.state {
                case .changed(let distance):
                    // Smaller distance = fingers closing = zoom out
                    // Map distance changes to zoom direction
                    if distance < 0.015 {
                        inputController.zoom(direction: .zoomIn)
                    } else {
                        inputController.zoom(direction: .zoomOut)
                    }
                case .began, .ended, .discrete:
                    break
                }

            case .fist:
                switch gesture.state {
                case .began:
                    isDragging = true
                    inputController.startDrag(at: cursorPosition)
                case .ended:
                    isDragging = false
                    inputController.endDrag(at: cursorPosition)
                case .changed, .discrete:
                    break
                }

            case .point:
                switch gesture.state {
                case .began:
                    isPointActive = true
                case .changed(let encodedPosition):
                    // Decode fingertip position: x + y * 10000
                    let y = encodedPosition / 10000.0
                    let x = encodedPosition - (y.rounded(.down) * 10000.0)
                    if let profile = calibrationProfile {
                        let screenPoint = GazePoint(
                            x: x * profile.screenWidth,
                            y: y * profile.screenHeight
                        )
                        currentCursorPosition = screenPoint
                        if isDragging {
                            inputController.dragMove(to: screenPoint)
                        } else {
                            inputController.moveCursor(to: screenPoint)
                        }
                    }
                case .ended:
                    isPointActive = false
                case .discrete:
                    break
                }

            case .openPalm:
                guard gesture.state == .discrete else { continue }
                handGesturesEnabled.toggle()
                activeGesture = nil
            }
        }

        // Clear active gesture after processing one-shot events
        if gestures.allSatisfy({ $0.state == .discrete || $0.state == .ended }) {
            activeGesture = nil
        }
    }
```

- [ ] **Step 3: Update handleFrame to process hand data and gestures**

Replace the existing `handleFrame` method with:

```swift
    private func handleFrame(_ result: FrameProcessor.FrameResult) {
        faceLostTime = nil
        faceConfidence = result.confidence
        activeExpressions = result.expressions

        // Update hand tracking state
        handDetected = !result.hands.isEmpty
        handCount = result.hands.count

        if result.confidence < 0.5 {
            lowConfidenceCount += 1
            if lowConfidenceCount > 30 { trackingState = .paused(reason: .poorLighting) }
        } else { lowConfidenceCount = 0 }

        guard let profile = calibrationProfile else {
            trackingState = .detecting
            return
        }
        trackingState = .tracking

        let modeEvents = modeManager.process(expressions: result.expressions)
        currentMode = modeManager.currentMode

        for event in modeEvents {
            handleModeEvent(event)
        }

        blinkDetector.isEnabled = (currentMode == .normal || currentMode == .commandPalette)
        headTiltProcessor.isEnabled = (currentMode == .normal)

        switch currentMode {
        case .normal, .commandPalette:
            handleNormalTracking(result, profile: profile)
        case .scroll:
            handleScrollMode(result, profile: profile)
        case .dictation:
            handleWinkClicks(result)
        }

        // Process hand gestures (runs alongside all modes)
        handleGestureEvents(result.gestures, cursorPosition: currentCursorPosition)
    }
```

- [ ] **Step 4: Suppress eye-gaze cursor during point gesture**

Update `handleNormalTracking` to skip cursor movement when point gesture is active. Replace the method with:

```swift
    private func handleNormalTracking(_ result: FrameProcessor.FrameResult, profile: CalibrationProfile) {
        // During point gesture, fingertip controls cursor — skip eye-gaze cursor
        if !isPointActive {
            let screenPoint = profile.mapToScreen(result.rawGaze)
            let smoothed = cursorSmoother.smooth(screenPoint)
            let tiltOffset = headTiltProcessor.process(rollDegrees: result.headRoll)
            let final = GazePoint(x: smoothed.x + tiltOffset.x, y: smoothed.y + tiltOffset.y)
            currentCursorPosition = final

            if isDragging {
                inputController.dragMove(to: final)
            } else {
                inputController.moveCursor(to: final)
            }
        }

        let avgEAR = (result.leftEAR + result.rightEAR) / 2.0
        let clickEvents = blinkDetector.update(ear: avgEAR, timestamp: result.timestamp)
        for event in clickEvents {
            switch event {
            case .leftClick: inputController.leftClick(at: currentCursorPosition)
            case .rightClick: inputController.rightClick(at: currentCursorPosition)
            case .doubleClick: inputController.doubleClick(at: currentCursorPosition)
            }
        }
        handleWinkClicks(result)
    }
```

```bash
swift build 2>&1 | head -20
```

---

### Task 7: HUD + MenuBar + AppState Updates
**Files:**
- Modify: `App/AppState.swift`
- Modify: `App/UI/HUDMinimalView.swift`
- Modify: `App/UI/HUDExpandedView.swift`
- Modify: `App/UI/MenuBarView.swift`

- [ ] **Step 1: Add handGesturesEnabled to AppState**

In `App/AppState.swift`, add a published property after the existing `hudExpanded` property:

```swift
    @Published public var handGesturesEnabled: Bool
```

In the `init()` method, add initialization after `self.hudExpanded = ...`:

```swift
        self.handGesturesEnabled = UserDefaults.standard.object(forKey: "handGesturesEnabled") as? Bool ?? true
```

Add a method after `toggleHUDExpanded()`:

```swift
    public func toggleHandGestures() {
        handGesturesEnabled.toggle()
        pipeline.handGesturesEnabled = handGesturesEnabled
        UserDefaults.standard.set(handGesturesEnabled, forKey: "handGesturesEnabled")
    }
```

- [ ] **Step 2: Update HUDMinimalView with hand gesture icon**

Replace the entire `HUDMinimalView` in `App/UI/HUDMinimalView.swift` with:

```swift
struct HUDMinimalView: View {
    let mode: InputMode
    let confidence: Float
    let activeExpression: ExpressionType?
    let activeGesture: GestureType?
    let handDetected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: modeIcon).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
            Circle().fill(confidenceColor).frame(width: 6, height: 6)
            if let expr = activeExpression {
                Image(systemName: expressionIcon(expr)).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).transition(.opacity)
            }
            if handDetected {
                Image(systemName: gestureIcon).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).transition(.opacity)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    private var modeIcon: String {
        switch mode { case .normal: "eye"; case .scroll: "scroll"; case .dictation: "mic"; case .commandPalette: "magnifyingglass" }
    }
    private var confidenceColor: Color {
        if confidence > 0.7 { return .green }; if confidence > 0.4 { return .yellow }; return .red
    }
    private func expressionIcon(_ type: ExpressionType) -> String {
        switch type { case .winkLeft, .winkRight: "eye.slash"; case .smile: "face.smiling"; case .browRaise: "eyebrow"; case .mouthOpen: "mouth" }
    }
    private var gestureIcon: String {
        guard let gesture = activeGesture else { return "hand.raised" }
        switch gesture {
        case .swipeLeft, .swipeRight: return "hand.point.left"
        case .swipeUp, .swipeDown: return "hand.point.up"
        case .pinch: return "hand.pinch"
        case .fist: return "hand.closed"
        case .point: return "hand.point.right"
        case .openPalm: return "hand.raised"
        }
    }
}
```

- [ ] **Step 3: Update HUDExpandedView with hand data section**

Replace the entire `HUDExpandedView` in `App/UI/HUDExpandedView.swift` with:

```swift
struct HUDExpandedView: View {
    let mode: InputMode
    let confidence: Float
    let expressions: [DetectedExpression]
    let cursorPosition: GazePoint
    let handCount: Int
    let activeGesture: GestureType?
    let handGesturesEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: modeIcon).font(.system(size: 16, weight: .semibold))
                Text(modeName).font(.system(size: 14, weight: .semibold))
                Spacer()
                Circle().fill(confidenceColor).frame(width: 8, height: 8)
                Text("\(Int(confidence * 100))%").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Divider().opacity(0.3)
            if expressions.isEmpty {
                Text("No expressions").font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                ForEach(expressions, id: \.type) { expr in
                    HStack(spacing: 6) {
                        Circle().fill(Color.blue).frame(width: 5, height: 5)
                        Text(expr.type.rawValue).font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text("\(Int(expr.confidence * 100))%").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
            Divider().opacity(0.3)
            HStack {
                Image(systemName: "hand.raised").font(.system(size: 12))
                Text("Hands: \(handCount)").font(.system(size: 11))
                Spacer()
                if let gesture = activeGesture {
                    Text(gesture.rawValue).font(.system(size: 10, design: .monospaced)).foregroundColor(.blue)
                } else {
                    Text(handGesturesEnabled ? "Listening" : "Paused").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            Divider().opacity(0.3)
            HStack {
                Text("Cursor").font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Text("(\(Int(cursorPosition.x)), \(Int(cursorPosition.y)))").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
        }
        .padding(14).frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    private var modeIcon: String {
        switch mode { case .normal: "eye"; case .scroll: "scroll"; case .dictation: "mic"; case .commandPalette: "magnifyingglass" }
    }
    private var modeName: String {
        switch mode { case .normal: "Normal"; case .scroll: "Scroll"; case .dictation: "Dictation"; case .commandPalette: "Command Palette" }
    }
    private var confidenceColor: Color {
        if confidence > 0.7 { return .green }; if confidence > 0.4 { return .yellow }; return .red
    }
}
```

- [ ] **Step 4: Update MenuBarView with hand gestures toggle**

In `App/UI/MenuBarView.swift`, add a "Hand Gestures" toggle after the "Show HUD" toggle. Add the following lines after the `Toggle("Show HUD", ...)` line:

```swift
            Toggle("Hand Gestures", isOn: Binding(
                get: { appState.handGesturesEnabled },
                set: { _ in appState.toggleHandGestures() }))
```

```bash
swift build 2>&1 | head -20
```

---

### Task 8: Update HUD Call Sites
**Files:**
- Modify: Any file that constructs `HUDMinimalView` or `HUDExpandedView`

- [ ] **Step 1: Find and update all HUDMinimalView construction sites**

```bash
cd /Users/angelorios/Desktop/Lucent && grep -rn "HUDMinimalView(" App/ --include="*.swift"
```

Update each call site to pass the new `activeGesture` and `handDetected` parameters. For example, if constructed in a parent HUD view:

```swift
HUDMinimalView(
    mode: pipeline.currentMode,
    confidence: pipeline.faceConfidence,
    activeExpression: pipeline.activeExpressions.first?.type,
    activeGesture: pipeline.activeGesture,
    handDetected: pipeline.handDetected
)
```

- [ ] **Step 2: Find and update all HUDExpandedView construction sites**

```bash
cd /Users/angelorios/Desktop/Lucent && grep -rn "HUDExpandedView(" App/ --include="*.swift"
```

Update each call site to pass the new parameters:

```swift
HUDExpandedView(
    mode: pipeline.currentMode,
    confidence: pipeline.faceConfidence,
    expressions: pipeline.activeExpressions,
    cursorPosition: pipeline.currentCursorPosition,
    handCount: pipeline.handCount,
    activeGesture: pipeline.activeGesture,
    handGesturesEnabled: pipeline.handGesturesEnabled
)
```

```bash
swift build 2>&1 | head -20
```

---

### Task 9: Final Integration Verification
**Files:**
- No new files

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/angelorios/Desktop/Lucent && swift test 2>&1 | tail -30
```

Fix any compilation errors or test failures before proceeding.

- [ ] **Step 2: Verify all new types are exported from LucentCore**

Check that `GestureType.swift` types are visible to the App target:

```bash
cd /Users/angelorios/Desktop/Lucent && grep -rn "import LucentCore" App/ --include="*.swift" | head -10
```

All public types in `Sources/LucentCore/Models/GestureType.swift` and `Sources/LucentCore/Tracking/HandDetector.swift` and `Sources/LucentCore/Tracking/GestureRecognizer.swift` should be accessible in the App target through the existing `import LucentCore`.

- [ ] **Step 3: Build the full project**

```bash
cd /Users/angelorios/Desktop/Lucent && swift build 2>&1
```

- [ ] **Step 4: Commit all changes**

```bash
cd /Users/angelorios/Desktop/Lucent && git add -A && git commit -m "Add Phase 3: hand tracking + gesture recognition

- HandDetector: VNDetectHumanHandPoseRequest wrapper with finger state classification
- GestureRecognizer: swipe, pinch, fist, point, open palm detection
- InputController: startDrag, endDrag, dragMove, switchDesktop, zoom, Mission Control, Expose
- FrameProcessor: hand detection + gesture recognition alongside face tracking
- TrackingPipeline: gesture event dispatch, point override, fist drag state
- HUD: hand icon, gesture display, hand count
- MenuBar: hand gestures toggle
- AppState: handGesturesEnabled persistence
- Tests: HandDetector finger state + angle tests, GestureRecognizer full gesture suite"
```

---

## Spec Coverage Checklist

| Spec Requirement | Task |
|---|---|
| VNDetectHumanHandPoseRequest hand detection | Task 2 (HandDetector.detect) |
| 21 joint landmarks per hand | Task 1 (HandJoint enum, 21 cases) |
| Finger state classification (extended/curled) from joint angles | Task 2 (HandDetector.classifyFinger) |
| Thumb uses 140-degree threshold | Task 2 (GestureConfig.thumbExtendedAngle) |
| Other fingers use 150-degree threshold | Task 2 (GestureConfig.fingerExtendedAngle) |
| Wrist velocity tracking | Task 2 (HandDetector.processHandObservation) |
| Swipe left/right/up/down detection | Task 3 (GestureRecognizer.detectSwipe) |
| Swipe displacement thresholds (30% X, 25% Y) | Task 1 (GestureConfig defaults) |
| Swipe requires all fingers extended | Task 3 (allFingersExtendedHistory check) |
| Swipe 500ms window + 500ms cooldown | Task 1 (GestureConfig) + Task 3 |
| Pinch detection (thumb-index < 0.03, others extended) | Task 3 (detectPinch) |
| Pinch continuous with distance tracking | Task 3 (GestureState.changed) |
| Fist detection (all curled, 300ms hold) | Task 3 (detectFist) |
| Fist began/ended events | Task 3 (fistActive state machine) |
| Point detection (index extended, others curled, 200ms) | Task 3 (detectPoint) |
| Point fingertip position in changed events | Task 3 (encodedPosition) |
| Open palm toggle (all extended, stationary, 500ms) | Task 3 (detectOpenPalm) |
| Swipe left/right maps to Ctrl+Arrow | Task 4 (switchDesktop) + Task 6 |
| Swipe up maps to Mission Control | Task 4 (triggerMissionControl) + Task 6 |
| Swipe down maps to App Expose | Task 4 (triggerExpose) + Task 6 |
| Pinch maps to Cmd+Plus/Minus | Task 4 (zoom) + Task 6 |
| Fist maps to click-and-drag | Task 4 (startDrag/endDrag) + Task 6 |
| Point overrides eye-gaze cursor | Task 6 (isPointActive in handleNormalTracking) |
| Open palm toggles handGesturesEnabled | Task 6 (handleGestureEvents .openPalm) |
| Hand detection in FrameProcessor | Task 5 (handDetector + gestureRecognizer) |
| FrameResult.hands + FrameResult.gestures | Task 5 (FrameResult expansion) |
| TrackingPipeline gesture dispatch | Task 6 (handleGestureEvents) |
| Simultaneous hand + face tracking | Task 5 (both run in process()) + Task 6 |
| Drag movement during fist | Task 6 (isDragging + dragMove) |
| HUDMinimalView hand icon | Task 7 (gestureIcon) |
| HUDExpandedView hand count + gesture name | Task 7 (hand data section) |
| MenuBarView hand gestures toggle | Task 7 (Toggle) |
| AppState handGesturesEnabled | Task 7 (property + persistence) |
| HandDetectorTests | Task 2 (joint angle + finger state + velocity tests) |
| GestureRecognizerTests | Task 3 (all gesture type tests + cooldown + hand lost) |
| GestureType.swift models | Task 1 (all enums + structs) |
| HandDetector.swift | Task 2 |
| GestureRecognizer.swift | Task 3 |
| Chirality (left/right hand) | Task 1 (Chirality enum) + Task 2 (parsing) |
| GestureConfig with all thresholds | Task 1 |
| SwipeDirection and ZoomDirection enums | Task 1 |
