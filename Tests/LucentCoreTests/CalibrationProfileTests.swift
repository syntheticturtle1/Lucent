import Foundation
import Testing
@testable import LucentCore

@Test func identityMappingReturnsInputScaled() {
    let profile = CalibrationProfile(
        xCoefficients: [0, 1920, 0, 0, 0, 0],
        yCoefficients: [0, 0, 1080, 0, 0, 0],
        cameraID: "test",
        screenWidth: 1920,
        screenHeight: 1080
    )
    let mapped = profile.mapToScreen(GazePoint(x: 0.5, y: 0.5))
    #expect(abs(mapped.x - 960) < 0.001)
    #expect(abs(mapped.y - 540) < 0.001)
}

@Test func mappingClampsToScreenBounds() {
    let profile = CalibrationProfile(
        xCoefficients: [0, 1920, 0, 0, 0, 0],
        yCoefficients: [0, 0, 1080, 0, 0, 0],
        cameraID: "test",
        screenWidth: 1920,
        screenHeight: 1080
    )
    let mapped = profile.mapToScreen(GazePoint(x: 2.0, y: -1.0))
    #expect(mapped.x == 1920)
    #expect(mapped.y == 0)
}

@Test func encodeDecode() throws {
    let original = CalibrationProfile(
        xCoefficients: [1, 2, 3, 4, 5, 6],
        yCoefficients: [6, 5, 4, 3, 2, 1],
        cameraID: "cam-abc",
        screenWidth: 2560,
        screenHeight: 1440
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(CalibrationProfile.self, from: data)
    #expect(decoded == original)
}
