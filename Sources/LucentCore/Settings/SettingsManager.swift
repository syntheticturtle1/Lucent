import Foundation

/// Central manager that owns the profile lifecycle: load, save, create, delete, switch.
/// Also applies profile settings to all tracking pipeline components.
public final class SettingsManager: @unchecked Sendable {

    // MARK: - Published State

    public var currentProfile: UserProfile
    public var availableProfiles: [UserProfile]
    public var activeProfileID: UUID

    // MARK: - Storage

    private let profilesDirectory: URL

    // MARK: - Init

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

    // MARK: - CRUD

    /// Load all profile JSON files from the profiles directory.
    public func loadProfiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: profilesDirectory, includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        var profiles: [UserProfile] = []

        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let profile = try? decoder.decode(UserProfile.self, from: data) {
                profiles.append(profile)
            }
        }

        guard !profiles.isEmpty else { return }

        availableProfiles = profiles.sorted { $0.createdAt < $1.createdAt }

        // Restore active profile from UserDefaults
        let storedID = UserDefaults.standard.string(forKey: "activeProfileID")
            .flatMap(UUID.init(uuidString:))

        if let id = storedID, let match = profiles.first(where: { $0.id == id }) {
            activeProfileID = id
            currentProfile = match
        } else {
            activeProfileID = profiles[0].id
            currentProfile = profiles[0]
        }
    }

    /// Save the current profile to disk and update the in-memory list.
    public func saveCurrentProfile() {
        if let idx = availableProfiles.firstIndex(where: { $0.id == currentProfile.id }) {
            availableProfiles[idx] = currentProfile
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(currentProfile) {
            let file = profilesDirectory.appendingPathComponent("\(currentProfile.id.uuidString).json")
            try? data.write(to: file)
        }

        UserDefaults.standard.set(activeProfileID.uuidString, forKey: "activeProfileID")
    }

    /// Create a new profile with default settings and the given name.
    @discardableResult
    public func createProfile(name: String) -> UserProfile {
        var profile = UserProfile.default
        profile.id = UUID()
        profile.name = name
        profile.createdAt = Date()
        profile.updatedAt = Date()
        availableProfiles.append(profile)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(profile) {
            let file = profilesDirectory.appendingPathComponent("\(profile.id.uuidString).json")
            try? data.write(to: file)
        }

        return profile
    }

    /// Delete a profile by ID. Will not delete the last remaining profile.
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

    /// Switch to a different profile by ID. Saves the current profile first.
    public func switchProfile(to id: UUID) {
        guard let profile = availableProfiles.first(where: { $0.id == id }) else { return }
        saveCurrentProfile()
        activeProfileID = id
        currentProfile = profile
        UserDefaults.standard.set(id.uuidString, forKey: "activeProfileID")
    }

    // MARK: - Apply to Components

    /// Apply current profile settings to a BlinkDetector.
    public func apply(to detector: BlinkDetector) {
        detector.earThreshold = currentProfile.earThreshold
        detector.quickBlinkMaxDuration = currentProfile.quickBlinkMaxDuration
        detector.longBlinkMaxDuration = currentProfile.longBlinkMaxDuration
        detector.doubleBlinkWindow = currentProfile.doubleBlinkWindow
        detector.cooldownDuration = currentProfile.blinkCooldown
        detector.sharpnessThreshold = currentProfile.blinkSharpness
    }

    /// Apply current profile settings to an ExpressionDetector.
    public func apply(to detector: ExpressionDetector) {
        detector.configs = currentProfile.typedExpressionConfigs
        detector.winkClosedThreshold = currentProfile.winkClosedThreshold
        detector.winkOpenThreshold = currentProfile.winkOpenThreshold
    }

    /// Apply current profile settings to a GestureRecognizer.
    public func apply(to recognizer: GestureRecognizer) {
        recognizer.config = currentProfile.gestureConfig
    }

    /// Apply current profile settings to a TapDetector.
    public func apply(to detector: TapDetector) {
        // TapDetector config is set via its config property
        detector.config = TapConfig(
            tapThreshold: detector.config.tapThreshold,
            returnThreshold: detector.config.returnThreshold,
            maxTapDuration: detector.config.maxTapDuration,
            tapCooldown: detector.config.tapCooldown,
            baselineWindowSize: detector.config.baselineWindowSize,
            minimumConfidence: detector.config.minimumConfidence
        )
    }

    /// Apply current profile settings to a HeadTiltProcessor.
    public func apply(to processor: HeadTiltProcessor) {
        processor.deadZoneDegrees = currentProfile.headTiltDeadZone
        processor.pixelsPerDegree = currentProfile.headTiltPixelsPerDegree
    }

    /// Create a new CursorSmoother configured from the current profile.
    /// CursorSmoother uses `let` properties, so we create a fresh instance.
    public func makeCursorSmoother() -> CursorSmoother {
        CursorSmoother(
            dwellRadius: currentProfile.dwellRadius,
            dwellTime: currentProfile.dwellTime,
            processNoise: currentProfile.cursorSmoothing,
            measurementNoise: currentProfile.cursorMeasurementNoise
        )
    }
}
