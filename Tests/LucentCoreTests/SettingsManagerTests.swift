import XCTest
@testable import LucentCore

final class SettingsManagerTests: XCTestCase {
    var tempDir: URL!
    var manager: SettingsManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LucentTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = SettingsManager(profilesDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Profile Lifecycle

    func testInitCreatesDefaultProfile() {
        XCTAssertFalse(manager.availableProfiles.isEmpty)
        XCTAssertEqual(manager.currentProfile.name, "Default")
    }

    func testSaveAndLoadProfile() throws {
        var profile = manager.currentProfile
        profile.cursorSpeed = 2.5
        manager.currentProfile = profile
        manager.saveCurrentProfile()

        let manager2 = SettingsManager(profilesDirectory: tempDir)
        let loaded = manager2.availableProfiles.first { $0.id == profile.id }
        XCTAssertEqual(loaded?.cursorSpeed, 2.5)
    }

    func testCreateProfile() {
        let newProfile = manager.createProfile(name: "Gaming")
        XCTAssertEqual(newProfile.name, "Gaming")
        XCTAssertEqual(manager.availableProfiles.count, 2)
    }

    func testDeleteProfile() {
        let second = manager.createProfile(name: "Second")
        XCTAssertEqual(manager.availableProfiles.count, 2)
        manager.deleteProfile(id: second.id)
        XCTAssertEqual(manager.availableProfiles.count, 1)
    }

    func testCannotDeleteLastProfile() {
        let id = manager.currentProfile.id
        manager.deleteProfile(id: id)
        XCTAssertEqual(manager.availableProfiles.count, 1, "Should not delete last profile")
    }

    func testSwitchProfile() {
        let second = manager.createProfile(name: "Second")
        manager.switchProfile(to: second.id)
        XCTAssertEqual(manager.currentProfile.id, second.id)
    }

    func testProfilePersistsToDisk() throws {
        manager.saveCurrentProfile()
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty, "Profile file should exist on disk")
    }

    func testDeleteRemovesFileFromDisk() throws {
        let second = manager.createProfile(name: "ToDelete")
        let filesBefore = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(filesBefore.count, 2)
        manager.deleteProfile(id: second.id)
        let filesAfter = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(filesAfter.count, 1)
    }

    func testSwitchProfileSavesPrevious() {
        var first = manager.currentProfile
        first.dwellRadius = 99.0
        manager.currentProfile = first
        let second = manager.createProfile(name: "Second")
        manager.switchProfile(to: second.id)

        // Reload and check first profile was saved
        let reloaded = SettingsManager(profilesDirectory: tempDir)
        let loadedFirst = reloaded.availableProfiles.first { $0.id == first.id }
        XCTAssertEqual(loadedFirst?.dwellRadius, 99.0)
    }

    // MARK: - Apply to Components

    func testApplyToBlinkDetector() {
        var profile = manager.currentProfile
        profile.earThreshold = 0.3
        profile.quickBlinkMaxDuration = 0.4
        profile.longBlinkMaxDuration = 1.2
        profile.doubleBlinkWindow = 1.5
        profile.blinkCooldown = 1.0
        profile.blinkSharpness = 0.1
        manager.currentProfile = profile

        let detector = BlinkDetector()
        manager.apply(to: detector)
        XCTAssertEqual(detector.earThreshold, 0.3)
        XCTAssertEqual(detector.quickBlinkMaxDuration, 0.4)
        XCTAssertEqual(detector.longBlinkMaxDuration, 1.2)
        XCTAssertEqual(detector.doubleBlinkWindow, 1.5)
        XCTAssertEqual(detector.cooldownDuration, 1.0)
        XCTAssertEqual(detector.sharpnessThreshold, 0.1)
    }

    func testApplyToExpressionDetector() {
        var profile = manager.currentProfile
        profile.winkClosedThreshold = 0.2
        profile.winkOpenThreshold = 0.3
        var smileConfig = profile.expressionConfig(for: .smile)
        smileConfig.holdDuration = 0.9
        profile.setExpressionConfig(smileConfig, for: .smile)
        manager.currentProfile = profile

        let detector = ExpressionDetector()
        manager.apply(to: detector)
        XCTAssertEqual(detector.winkClosedThreshold, 0.2)
        XCTAssertEqual(detector.winkOpenThreshold, 0.3)
        XCTAssertEqual(detector.configs[.smile]?.holdDuration, 0.9)
    }

    func testApplyToGestureRecognizer() {
        var profile = manager.currentProfile
        var gc = profile.gestureConfig
        gc.pinchThreshold = 0.05
        gc.fistHoldDuration = 0.5
        profile.gestureConfig = gc
        manager.currentProfile = profile

        let recognizer = GestureRecognizer()
        manager.apply(to: recognizer)
        XCTAssertEqual(recognizer.config.pinchThreshold, 0.05)
        XCTAssertEqual(recognizer.config.fistHoldDuration, 0.5)
    }

    func testApplyToHeadTiltProcessor() {
        var profile = manager.currentProfile
        profile.headTiltDeadZone = 5.0
        profile.headTiltPixelsPerDegree = 1.5
        manager.currentProfile = profile

        let processor = HeadTiltProcessor()
        manager.apply(to: processor)
        XCTAssertEqual(processor.deadZoneDegrees, 5.0)
        XCTAssertEqual(processor.pixelsPerDegree, 1.5)
    }

    func testMakeCursorSmoother() {
        var profile = manager.currentProfile
        profile.dwellRadius = 50.0
        profile.dwellTime = 0.4
        profile.cursorSmoothing = 3.0
        profile.cursorMeasurementNoise = 10.0
        manager.currentProfile = profile

        let smoother = manager.makeCursorSmoother()
        // Verify by using smoother - it should work without crashing
        let raw = GazePoint(x: 100, y: 100)
        let result = smoother.smooth(raw)
        XCTAssertEqual(result.x, 100.0)
        XCTAssertEqual(result.y, 100.0)
    }

    // MARK: - Expression Config Round Trip

    func testExpressionConfigRoundTrips() throws {
        var profile = manager.currentProfile
        var smileConfig = profile.expressionConfig(for: .smile)
        smileConfig.holdDuration = 0.8
        smileConfig.cooldown = 0.7
        profile.setExpressionConfig(smileConfig, for: .smile)
        manager.currentProfile = profile
        manager.saveCurrentProfile()

        let manager2 = SettingsManager(profilesDirectory: tempDir)
        if let loaded = manager2.availableProfiles.first(where: { $0.id == profile.id }) {
            XCTAssertEqual(loaded.expressionConfig(for: .smile).holdDuration, 0.8)
            XCTAssertEqual(loaded.expressionConfig(for: .smile).cooldown, 0.7)
        } else {
            XCTFail("Profile not found after reload")
        }
    }

    func testGestureConfigRoundTrips() throws {
        var profile = manager.currentProfile
        var gc = GestureConfig.defaults
        gc.swipeDisplacementX = 0.5
        gc.pinchThreshold = 0.07
        profile.gestureConfig = gc
        manager.currentProfile = profile
        manager.saveCurrentProfile()

        let manager2 = SettingsManager(profilesDirectory: tempDir)
        if let loaded = manager2.availableProfiles.first(where: { $0.id == profile.id }) {
            XCTAssertEqual(loaded.gestureConfig.swipeDisplacementX, 0.5)
            XCTAssertEqual(loaded.gestureConfig.pinchThreshold, 0.07)
        } else {
            XCTFail("Profile not found after reload")
        }
    }

    // MARK: - Presets

    func testBeginnerPreset() {
        let beginner = UserProfile.beginner()
        XCTAssertEqual(beginner.name, "Beginner")
        XCTAssertGreaterThan(beginner.dwellRadius, UserProfile.default.dwellRadius)
        XCTAssertGreaterThan(beginner.blinkCooldown, UserProfile.default.blinkCooldown)
    }

    func testAdvancedPreset() {
        let advanced = UserProfile.advanced()
        XCTAssertEqual(advanced.name, "Advanced")
        XCTAssertLessThan(advanced.dwellRadius, UserProfile.default.dwellRadius)
        XCTAssertLessThan(advanced.blinkCooldown, UserProfile.default.blinkCooldown)
    }

    func testDefaultProfileMatchesComponentDefaults() {
        let profile = UserProfile.default
        XCTAssertEqual(profile.earThreshold, 0.2)
        XCTAssertEqual(profile.quickBlinkMaxDuration, 0.3)
        XCTAssertEqual(profile.dwellRadius, 30.0)
        XCTAssertEqual(profile.dwellTime, 0.2)
        XCTAssertEqual(profile.cursorSmoothing, 2.0)
        XCTAssertEqual(profile.cursorMeasurementNoise, 8.0)
        XCTAssertEqual(profile.headTiltDeadZone, 3.0)
        XCTAssertEqual(profile.headTiltPixelsPerDegree, 0.7)
        XCTAssertEqual(profile.winkClosedThreshold, 0.15)
        XCTAssertEqual(profile.winkOpenThreshold, 0.22)
    }
}
