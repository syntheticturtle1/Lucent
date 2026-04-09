// Tests/LucentCoreTests/CursorSmootherTests.swift
import Testing
@testable import LucentCore

@Test func stationaryInputConverges() {
    let smoother = CursorSmoother()
    var lastOutput = GazePoint.zero
    for _ in 0..<30 {
        lastOutput = smoother.smooth(GazePoint(x: 500, y: 300))
    }
    #expect(abs(lastOutput.x - 500) < 5)
    #expect(abs(lastOutput.y - 300) < 5)
}

@Test func jitteryInputIsSmoothed() {
    let smoother = CursorSmoother()
    for _ in 0..<20 { _ = smoother.smooth(GazePoint(x: 500, y: 300)) }
    var outputs: [GazePoint] = []
    for i in 0..<20 {
        let jitter = Double(i % 2 == 0 ? 50 : -50)
        outputs.append(smoother.smooth(GazePoint(x: 500 + jitter, y: 300 + jitter)))
    }
    let meanX = outputs.map(\.x).reduce(0, +) / Double(outputs.count)
    let variance = outputs.map { ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +) / Double(outputs.count)
    #expect(variance < 50 * 50, "Smoothed variance should be much less than raw jitter")
}

@Test func dwellZoneLocksCursor() {
    let smoother = CursorSmoother(dwellRadius: 30, dwellTime: 0.2)
    for _ in 0..<30 { _ = smoother.smooth(GazePoint(x: 500, y: 300)) }
    let output1 = smoother.smooth(GazePoint(x: 510, y: 305))
    let output2 = smoother.smooth(GazePoint(x: 495, y: 298))
    let output3 = smoother.smooth(GazePoint(x: 505, y: 302))
    let spread = output1.distance(to: output3)
    #expect(spread < 30, "Dwell zone should constrain cursor movement")
}

@Test func largeMovementBreaksDwellZone() {
    let smoother = CursorSmoother(dwellRadius: 30, dwellTime: 0.2)
    for _ in 0..<30 { _ = smoother.smooth(GazePoint(x: 500, y: 300)) }
    for _ in 0..<15 { _ = smoother.smooth(GazePoint(x: 800, y: 600)) }
    let output = smoother.smooth(GazePoint(x: 800, y: 600))
    #expect(output.x > 600, "Cursor should follow large movement")
}

@Test func fastMovementGetsLessSmoothing() {
    let smootherFast = CursorSmoother()
    let smootherSlow = CursorSmoother()
    for _ in 0..<20 {
        _ = smootherFast.smooth(GazePoint(x: 100, y: 100))
        _ = smootherSlow.smooth(GazePoint(x: 100, y: 100))
    }
    let fastOutput = smootherFast.smooth(GazePoint(x: 900, y: 900))
    let slowOutput = smootherSlow.smooth(GazePoint(x: 120, y: 120))
    let fastDist = fastOutput.distance(to: GazePoint(x: 100, y: 100))
    let slowDist = slowOutput.distance(to: GazePoint(x: 100, y: 100))
    #expect(fastDist > slowDist, "Fast saccades should be smoothed less")
}
