import Testing
import CoreGraphics
@testable import LucentCore

// --- EAR Tests ---

@Test func earOpenEyeReturnsHighValue() {
    let points = makeEyePoints(verticalScale: 1.0)
    let ear = BlinkDetector.computeEAR(eyePoints: points)
    #expect(ear > 0.25)
}

@Test func earClosedEyeReturnsLowValue() {
    let points = makeEyePoints(verticalScale: 0.05)
    let ear = BlinkDetector.computeEAR(eyePoints: points)
    #expect(ear < 0.1)
}

// --- Blink Classification Tests ---

@Test func quickBlinkProducesLeftClick() {
    let detector = BlinkDetector()
    let events = simulateBlink(detector: detector, closedFrames: 6, fps: 30)
    #expect(events.contains(.leftClick))
}

@Test func longBlinkProducesRightClick() {
    let detector = BlinkDetector()
    let events = simulateBlink(detector: detector, closedFrames: 15, fps: 30)
    #expect(events.contains(.rightClick))
}

@Test func doubleBlinkProducesDoubleClick() {
    let detector = BlinkDetector()
    var allEvents: [BlinkDetector.ClickEvent] = []
    allEvents += simulateBlink(detector: detector, closedFrames: 5, fps: 30)
    // Small gap (5 frames ~ 167ms)
    for _ in 0..<5 {
        allEvents += detector.update(ear: 0.3, timestamp: detector.lastTimestamp + 1.0/30.0)
    }
    allEvents += simulateBlink(detector: detector, closedFrames: 5, fps: 30)
    #expect(allEvents.contains(.doubleClick))
}

@Test func naturalBlinkIsFiltered() {
    let detector = BlinkDetector()
    var events: [BlinkDetector.ClickEvent] = []
    let timestamps = stride(from: 0.0, through: 0.3, by: 1.0/30.0)
    for (i, t) in timestamps.enumerated() {
        let ear: Double
        if i < 3 { ear = 0.3 - Double(i) * 0.03 }
        else if i < 6 { ear = 0.21 - Double(i - 3) * 0.04 }
        else { ear = 0.1 + Double(i - 6) * 0.04 }
        events += detector.update(ear: ear, timestamp: t)
    }
    #expect(events.isEmpty, "Natural gentle blink should be filtered")
}

@Test func cooldownPreventsDoubleTrigger() {
    let detector = BlinkDetector()
    let events1 = simulateBlink(detector: detector, closedFrames: 5, fps: 30)
    #expect(events1.contains(.leftClick))
    let events2 = simulateBlink(detector: detector, closedFrames: 5, fps: 30)
    #expect(events2.isEmpty, "Should be suppressed by cooldown")
}

// MARK: - Helpers

private func makeEyePoints(verticalScale: Double) -> [CGPoint] {
    let cx = 0.5, cy = 0.5
    let rx = 0.05
    let ry = 0.02 * verticalScale
    return (0..<8).map { i in
        let angle = Double(i) * (.pi * 2.0 / 8.0)
        return CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle))
    }
}

private func simulateBlink(detector: BlinkDetector, closedFrames: Int, fps: Double) -> [BlinkDetector.ClickEvent] {
    let dt = 1.0 / fps
    var events: [BlinkDetector.ClickEvent] = []
    // 5 open frames
    for _ in 0..<5 {
        events += detector.update(ear: 0.3, timestamp: detector.lastTimestamp + dt)
    }
    // Closed frames (sharp drop for intentional blink)
    for _ in 0..<closedFrames {
        events += detector.update(ear: 0.05, timestamp: detector.lastTimestamp + dt)
    }
    // 10 open frames
    for _ in 0..<10 {
        events += detector.update(ear: 0.3, timestamp: detector.lastTimestamp + dt)
    }
    return events
}
