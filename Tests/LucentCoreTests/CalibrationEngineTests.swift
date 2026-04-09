import Testing
@testable import LucentCore

@Test func fittingLinearDataRecoversCoefficients() {
    let engine = CalibrationEngine(screenWidth: 1000, screenHeight: 1000)
    let gazePoints = [
        GazePoint(x: 0.0, y: 0.0), GazePoint(x: 0.5, y: 0.0), GazePoint(x: 1.0, y: 0.0),
        GazePoint(x: 0.0, y: 0.5), GazePoint(x: 0.5, y: 0.5), GazePoint(x: 1.0, y: 0.5),
        GazePoint(x: 0.0, y: 1.0), GazePoint(x: 0.5, y: 1.0), GazePoint(x: 1.0, y: 1.0),
    ]
    let screenPoints = gazePoints.map { GazePoint(x: $0.x * 1000, y: $0.y * 1000) }
    let profile = engine.fit(gazePoints: gazePoints, screenPoints: screenPoints, cameraID: "test")
    let mapped = profile.mapToScreen(GazePoint(x: 0.3, y: 0.7))
    #expect(abs(mapped.x - 300) < 1.0)
    #expect(abs(mapped.y - 700) < 1.0)
}

@Test func fittingQuadraticDataRecoversMapping() {
    let engine = CalibrationEngine(screenWidth: 500, screenHeight: 500)
    var gazePoints: [GazePoint] = []
    var screenPoints: [GazePoint] = []
    for gx in stride(from: 0.0, through: 1.0, by: 0.25) {
        for gy in stride(from: 0.0, through: 1.0, by: 0.25) {
            gazePoints.append(GazePoint(x: gx, y: gy))
            screenPoints.append(GazePoint(x: 500 * gx * gx, y: 500 * gy * gy))
        }
    }
    let profile = engine.fit(gazePoints: gazePoints, screenPoints: screenPoints, cameraID: "test")
    let mapped = profile.mapToScreen(GazePoint(x: 0.6, y: 0.4))
    #expect(abs(mapped.x - 500 * 0.36) < 5.0)
    #expect(abs(mapped.y - 500 * 0.16) < 5.0)
}

@Test func calibrationPointCollectionAndFitting() {
    let engine = CalibrationEngine(screenWidth: 1920, screenHeight: 1080)
    let targets = engine.calibrationTargets()
    #expect(targets.count == 9)
    for target in targets {
        let gazeX = target.x / 1920.0
        let gazeY = target.y / 1080.0
        for _ in 0..<60 {
            engine.addSample(
                rawGaze: GazePoint(x: gazeX + Double.random(in: -0.01...0.01),
                                   y: gazeY + Double.random(in: -0.01...0.01)),
                targetIndex: engine.currentTargetIndex
            )
        }
        engine.advanceTarget()
    }
    let profile = engine.buildProfile(cameraID: "test-cam")
    #expect(profile != nil)
    let mapped = profile!.mapToScreen(GazePoint(x: 0.5, y: 0.5))
    #expect(abs(mapped.x - 960) < 50)
    #expect(abs(mapped.y - 540) < 50)
}

@Test func outlierRejectionRemovesExtremes() {
    let engine = CalibrationEngine(screenWidth: 1000, screenHeight: 1000)
    var samples = (0..<58).map { _ in
        GazePoint(x: 0.5 + Double.random(in: -0.01...0.01),
                  y: 0.5 + Double.random(in: -0.01...0.01))
    }
    samples.append(GazePoint(x: 10.0, y: 10.0))
    samples.append(GazePoint(x: -5.0, y: -5.0))
    let cleaned = CalibrationEngine.rejectOutliers(samples)
    #expect(cleaned.count >= 55)
    #expect(cleaned.count <= 58)
    #expect(!cleaned.contains(where: { $0.x > 1.0 || $0.x < 0.0 }))
}
