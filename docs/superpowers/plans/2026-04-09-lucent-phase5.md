# Lucent Phase 5 Implementation Plan

## Task 1: UserProfile Model

**Files:** `Sources/LucentCore/Models/UserProfile.swift`

- [ ] Create `UserProfile` struct with all settings fields
- [ ] Add `Codable`, `Equatable`, `Sendable` conformance  
- [ ] Add `static let default` with all hardcoded defaults from existing components
- [ ] Add sensitivity presets: `beginner`, `normal`, `advanced`
- [ ] Verify `swift test` passes

```swift
// Sources/LucentCore/Models/UserProfile.swift
import Foundation

public struct UserProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - General
    public var launchAtLogin: Bool
    public var autoStartTracking: Bool
    public var pauseOnScreenLock: Bool
    public var selectedCameraID: String?

    // MARK: - Cursor
    public var cursorSmoothing: Double
    public var cursorMeasurementNoise: Double
    public var dwellRadius: Double
    public var dwellTime: Double
    public var cursorSpeed: Double

    // MARK: - Click (Blink)
    public var earThreshold: Double
    public var quickBlinkMaxDuration: Double
    public var longBlinkMaxDuration: Double
    public var doubleBlinkWindow: Double
    public var blinkCooldown: Double
    public var blinkSharpness: Double

    // MARK: - Expressions
    public var expressionConfigs: [String: ExpressionConfig]
    public var winkClosedThreshold: Double
    public var winkOpenThreshold: Double

    // MARK: - Gestures
    public var gestureConfig: GestureConfig
    public var handGesturesEnabled: Bool

    // MARK: - HUD
    public var showHUD: Bool
    public var hudExpanded: Bool

    // MARK: - Keyboard
    public var keyboardEnabled: Bool
    public var keySize: Double
    public var predictionBarEnabled: Bool

    // MARK: - Head Tilt
    public var headTiltDeadZone: Double
    public var headTiltPixelsPerDegree: Double

    public init(
        id: UUID = UUID(),
        name: String = "Default",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        launchAtLogin: Bool = false,
        autoStartTracking: Bool = false,
        pauseOnScreenLock: Bool = true,
        selectedCameraID: String? = nil,
        cursorSmoothing: Double = 2.0,
        cursorMeasurementNoise: Double = 8.0,
        dwellRadius: Double = 30.0,
        dwellTime: Double = 0.2,
        cursorSpeed: Double = 1.0,
        earThreshold: Double = 0.2,
        quickBlinkMaxDuration: Double = 0.3,
        longBlinkMaxDuration: Double = 0.8,
        doubleBlinkWindow: Double = 1.0,
        blinkCooldown: Double = 0.75,
        blinkSharpness: Double = 0.08,
        expressionConfigs: [String: ExpressionConfig]? = nil,
        winkClosedThreshold: Double = 0.15,
        winkOpenThreshold: Double = 0.22,
        gestureConfig: GestureConfig = .defaults,
        handGesturesEnabled: Bool = true,
        showHUD: Bool = true,
        hudExpanded: Bool = false,
        keyboardEnabled: Bool = false,
        keySize: Double = 1.0,
        predictionBarEnabled: Bool = true,
        headTiltDeadZone: Double = 3.0,
        headTiltPixelsPerDegree: Double = 0.7
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.launchAtLogin = launchAtLogin
        self.autoStartTracking = autoStartTracking
        self.pauseOnScreenLock = pauseOnScreenLock
        self.selectedCameraID = selectedCameraID
        self.cursorSmoothing = cursorSmoothing
        self.cursorMeasurementNoise = cursorMeasurementNoise
        self.dwellRadius = dwellRadius
        self.dwellTime = dwellTime
        self.cursorSpeed = cursorSpeed
        self.earThreshold = earThreshold
        self.quickBlinkMaxDuration = quickBlinkMaxDuration
        self.longBlinkMaxDuration = longBlinkMaxDuration
        self.doubleBlinkWindow = doubleBlinkWindow
        self.blinkCooldown = blinkCooldown
        self.blinkSharpness = blinkSharpness
        self.expressionConfigs = expressionConfigs ?? Self.defaultExpressionConfigs
        self.winkClosedThreshold = winkClosedThreshold
        self.winkOpenThreshold = winkOpenThreshold
        self.gestureConfig = gestureConfig
        self.handGesturesEnabled = handGesturesEnabled
        self.showHUD = showHUD
        self.hudExpanded = hudExpanded
        self.keyboardEnabled = keyboardEnabled
        self.keySize = keySize
        self.predictionBarEnabled = predictionBarEnabled
        self.headTiltDeadZone = headTiltDeadZone
        self.headTiltPixelsPerDegree = headTiltPixelsPerDegree
    }

    // Use String keys for Codable compatibility
    private static var defaultExpressionConfigs: [String: ExpressionConfig] {
        var configs: [String: ExpressionConfig] = [:]
        for (type, config) in ExpressionConfig.defaults {
            configs[type.rawValue] = config
        }
        return configs
    }

    public func expressionConfig(for type: ExpressionType) -> ExpressionConfig {
        expressionConfigs[type.rawValue] ?? ExpressionConfig.defaults[type]!
    }

    public mutating func setExpressionConfig(_ config: ExpressionConfig, for type: ExpressionType) {
        expressionConfigs[type.rawValue] = config
        updatedAt = Date()
    }

    public static let `default` = UserProfile()

    // Presets
    public static func beginner() -> UserProfile {
        UserProfile(
            name: "Beginner",
            cursorSmoothing: 1.0,
            cursorMeasurementNoise: 12.0,
            dwellRadius: 45.0,
            dwellTime: 0.35,
            cursorSpeed: 0.8,
            quickBlinkMaxDuration: 0.4,
            longBlinkMaxDuration: 1.0,
            blinkCooldown: 1.0,
            blinkSharpness: 0.06
        )
    }

    public static func advanced() -> UserProfile {
        UserProfile(
            name: "Advanced",
            cursorSmoothing: 3.0,
            cursorMeasurementNoise: 5.0,
            dwellRadius: 20.0,
            dwellTime: 0.12,
            cursorSpeed: 1.3,
            quickBlinkMaxDuration: 0.25,
            longBlinkMaxDuration: 0.6,
            blinkCooldown: 0.5,
            blinkSharpness: 0.1
        )
    }
}
```

## Task 2: SettingsManager (TDD)

**Files:** `Sources/LucentCore/Settings/SettingsManager.swift`, `Tests/LucentCoreTests/SettingsManagerTests.swift`

- [ ] Write tests first: load/save/create/delete/switch profiles
- [ ] Implement SettingsManager
- [ ] Verify `swift test` passes

```swift
// Tests/LucentCoreTests/SettingsManagerTests.swift
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
        manager2.loadProfiles()
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

    func testApplyToBlinkDetector() {
        var profile = manager.currentProfile
        profile.earThreshold = 0.3
        profile.quickBlinkMaxDuration = 0.4
        profile.blinkCooldown = 1.0
        profile.blinkSharpness = 0.1
        manager.currentProfile = profile

        let detector = BlinkDetector()
        manager.apply(to: detector)
        XCTAssertEqual(detector.earThreshold, 0.3)
        XCTAssertEqual(detector.quickBlinkMaxDuration, 0.4)
        XCTAssertEqual(detector.cooldownDuration, 1.0)
        XCTAssertEqual(detector.sharpnessThreshold, 0.1)
    }

    func testApplyToExpressionDetector() {
        var profile = manager.currentProfile
        profile.winkClosedThreshold = 0.2
        manager.currentProfile = profile

        let detector = ExpressionDetector()
        manager.apply(to: detector)
        XCTAssertEqual(detector.winkClosedThreshold, 0.2)
    }

    func testApplyToGestureRecognizer() {
        var profile = manager.currentProfile
        var gc = profile.gestureConfig
        gc.pinchThreshold = 0.05
        profile.gestureConfig = gc
        manager.currentProfile = profile

        let recognizer = GestureRecognizer()
        manager.apply(to: recognizer)
        XCTAssertEqual(recognizer.config.pinchThreshold, 0.05)
    }

    func testApplyToTapDetector() {
        var profile = manager.currentProfile
        manager.currentProfile = profile

        let detector = TapDetector()
        manager.apply(to: detector)
        XCTAssertEqual(detector.config.tapThreshold, TapConfig.defaults.tapThreshold)
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

    func testProfilePersistsToDisk() throws {
        manager.saveCurrentProfile()
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty, "Profile file should exist on disk")
    }

    func testExpressionConfigRoundTrips() throws {
        var profile = manager.currentProfile
        var smileConfig = profile.expressionConfig(for: .smile)
        smileConfig.holdDuration = 0.8
        profile.setExpressionConfig(smileConfig, for: .smile)
        manager.currentProfile = profile
        manager.saveCurrentProfile()

        let manager2 = SettingsManager(profilesDirectory: tempDir)
        manager2.loadProfiles()
        if let loaded = manager2.availableProfiles.first(where: { $0.id == profile.id }) {
            XCTAssertEqual(loaded.expressionConfig(for: .smile).holdDuration, 0.8)
        } else {
            XCTFail("Profile not found after reload")
        }
    }
}
```

```swift
// Sources/LucentCore/Settings/SettingsManager.swift
import Foundation

public final class SettingsManager: @unchecked Sendable {
    public var currentProfile: UserProfile
    public var availableProfiles: [UserProfile]
    public var activeProfileID: UUID

    private let profilesDirectory: URL

    public init(profilesDirectory: URL? = nil) {
        let dir = profilesDirectory ?? Self.defaultProfilesDirectory
        self.profilesDirectory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        self.availableProfiles = []
        self.currentProfile = .default
        self.activeProfileID = self.currentProfile.id

        loadProfiles()

        if availableProfiles.isEmpty {
            availableProfiles = [.default]
            activeProfileID = UserProfile.default.id
            currentProfile = .default
            saveCurrentProfile()
        }
    }

    private static var defaultProfilesDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Lucent/profiles", isDirectory: true)
    }

    public func loadProfiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: profilesDirectory, includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        var profiles: [UserProfile] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let profile = try? decoder.decode(UserProfile.self, from: data) {
                profiles.append(profile)
            }
        }
        if !profiles.isEmpty {
            availableProfiles = profiles.sorted { $0.createdAt < $1.createdAt }
            let storedID = UserDefaults.standard.string(forKey: "activeProfileID")
                .flatMap(UUID.init(uuidString:))
            if let id = storedID, profiles.contains(where: { $0.id == id }) {
                activeProfileID = id
                currentProfile = profiles.first { $0.id == id }!
            } else {
                activeProfileID = profiles[0].id
                currentProfile = profiles[0]
            }
        }
    }

    public func saveCurrentProfile() {
        // Update the profile in the list
        if let idx = availableProfiles.firstIndex(where: { $0.id == currentProfile.id }) {
            availableProfiles[idx] = currentProfile
        }
        // Write to disk
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(currentProfile) {
            let file = profilesDirectory.appendingPathComponent("\(currentProfile.id.uuidString).json")
            try? data.write(to: file)
        }
        UserDefaults.standard.set(activeProfileID.uuidString, forKey: "activeProfileID")
    }

    @discardableResult
    public func createProfile(name: String) -> UserProfile {
        var profile = UserProfile.default
        profile.id = UUID()
        profile.name = name
        profile.createdAt = Date()
        profile.updatedAt = Date()
        availableProfiles.append(profile)
        // Save to disk
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(profile) {
            let file = profilesDirectory.appendingPathComponent("\(profile.id.uuidString).json")
            try? data.write(to: file)
        }
        return profile
    }

    public func deleteProfile(id: UUID) {
        guard availableProfiles.count > 1 else { return }
        availableProfiles.removeAll { $0.id == id }
        let file = profilesDirectory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
        if activeProfileID == id {
            let first = availableProfiles[0]
            activeProfileID = first.id
            currentProfile = first
            UserDefaults.standard.set(activeProfileID.uuidString, forKey: "activeProfileID")
        }
    }

    public func switchProfile(to id: UUID) {
        guard let profile = availableProfiles.first(where: { $0.id == id }) else { return }
        saveCurrentProfile()
        activeProfileID = id
        currentProfile = profile
        UserDefaults.standard.set(id.uuidString, forKey: "activeProfileID")
    }

    // MARK: - Apply to Components

    public func apply(to detector: BlinkDetector) {
        detector.earThreshold = currentProfile.earThreshold
        detector.quickBlinkMaxDuration = currentProfile.quickBlinkMaxDuration
        detector.longBlinkMaxDuration = currentProfile.longBlinkMaxDuration
        detector.doubleBlinkWindow = currentProfile.doubleBlinkWindow
        detector.cooldownDuration = currentProfile.blinkCooldown
        detector.sharpnessThreshold = currentProfile.blinkSharpness
    }

    public func apply(to detector: ExpressionDetector) {
        var configs: [ExpressionType: ExpressionConfig] = [:]
        for type in ExpressionType.allCases {
            configs[type] = currentProfile.expressionConfig(for: type)
        }
        detector.configs = configs
        detector.winkClosedThreshold = currentProfile.winkClosedThreshold
        detector.winkOpenThreshold = currentProfile.winkOpenThreshold
    }

    public func apply(to recognizer: GestureRecognizer) {
        recognizer.config = currentProfile.gestureConfig
    }

    public func apply(to detector: TapDetector) {
        detector.config = TapConfig(
            tapThreshold: detector.config.tapThreshold,
            returnThreshold: detector.config.returnThreshold,
            maxTapDuration: detector.config.maxTapDuration,
            tapCooldown: detector.config.tapCooldown,
            baselineWindowSize: detector.config.baselineWindowSize,
            minimumConfidence: detector.config.minimumConfidence
        )
    }

    public func apply(to processor: HeadTiltProcessor) {
        processor.deadZoneDegrees = currentProfile.headTiltDeadZone
        processor.pixelsPerDegree = currentProfile.headTiltPixelsPerDegree
    }

    public func makeCursorSmoother() -> CursorSmoother {
        CursorSmoother(
            dwellRadius: currentProfile.dwellRadius,
            dwellTime: currentProfile.dwellTime,
            processNoise: currentProfile.cursorSmoothing,
            measurementNoise: currentProfile.cursorMeasurementNoise
        )
    }
}
```

## Task 3: Component applySettings Methods

**Files:** Modified: `App/TrackingPipeline.swift`

- [ ] Add `applySettings(_ profile: UserProfile)` to TrackingPipeline
- [ ] Wire CursorSmoother recreation
- [ ] Wire BlinkDetector, ExpressionDetector, GestureRecognizer, TapDetector, HeadTiltProcessor updates
- [ ] Verify `swift test` passes (existing 121 tests)

TrackingPipeline changes:
- Make `blinkDetector`, `cursorSmoother`, `headTiltProcessor` non-private where needed
- Add public `settingsManager` property
- Add `applySettings` method that delegates to SettingsManager apply methods

## Task 4: SettingsView Full Rewrite

**Files:** `App/UI/SettingsView.swift` (complete rewrite)

- [ ] Replace all 5 existing tabs with 8 new tabs
- [ ] Wire all bindings through SettingsManager
- [ ] Remove all `.constant()` bindings
- [ ] Verify `xcodegen generate && xcodebuild build` succeeds

Tabs: General, Tracking, Cursor, Click, Expressions, Gestures, Keyboard, Calibration
Each tab reads/writes `settingsManager.currentProfile` fields via Binding helpers.

## Task 5: OnboardingView

**Files:** `App/UI/OnboardingView.swift` (new), Modified: `App/UI/FirstLaunchWizard.swift` (retired), Modified: `App/LucentApp.swift`

- [ ] Create 6-step OnboardingView
- [ ] Steps: Welcome, Camera, Accessibility, Profile Setup, Calibration, Complete
- [ ] Profile setup step includes name field and sensitivity preset picker
- [ ] Wire into LucentApp to replace FirstLaunchWizard
- [ ] Verify `xcodegen generate && xcodebuild build` succeeds

## Task 6: ProfilePickerView

**Files:** `App/UI/ProfilePickerView.swift` (new)

- [ ] Profile list with radio button selection
- [ ] New profile button
- [ ] Delete button with confirmation alert
- [ ] Inline name editing
- [ ] Embed in General tab of SettingsView
- [ ] Verify `xcodegen generate && xcodebuild build` succeeds

## Task 7: Pipeline + AppState Integration

**Files:** Modified: `App/AppState.swift`, Modified: `App/TrackingPipeline.swift`

- [ ] Add `settingsManager` to AppState
- [ ] Replace individual UserDefaults reads with profile reads
- [ ] Wire settings changes to pipeline
- [ ] Auto-save on profile changes
- [ ] Verify `xcodegen generate && xcodebuild build` succeeds

## Task 8: Final Integration

- [ ] Run full `swift test` -- all existing tests + new SettingsManager tests pass
- [ ] Run `xcodegen generate && xcodebuild build` -- clean build
- [ ] Verify no regressions in tracking pipeline behavior
- [ ] Commit and verify
