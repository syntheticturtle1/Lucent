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
