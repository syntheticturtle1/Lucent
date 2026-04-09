import Foundation

/// Stores all configurable settings in one Codable struct.
/// Persisted as JSON in ~/Library/Application Support/Lucent/profiles/.
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

    /// Kalman process noise (higher = less smoothing). Range: 0.5...10.0
    public var cursorSmoothing: Double
    /// Kalman measurement noise (higher = more smoothing). Range: 1.0...20.0
    public var cursorMeasurementNoise: Double
    /// Dwell zone radius in pixels. Range: 10...80
    public var dwellRadius: Double
    /// Time in seconds to lock dwell zone. Range: 0.05...1.0
    public var dwellTime: Double
    /// Cursor speed multiplier. Range: 0.5...3.0
    public var cursorSpeed: Double

    // MARK: - Click (Blink)

    /// EAR value below which eye is considered closed. Range: 0.1...0.4
    public var earThreshold: Double
    /// Maximum quick blink duration in seconds. Range: 0.1...0.5
    public var quickBlinkMaxDuration: Double
    /// Maximum long blink duration in seconds. Range: 0.4...1.5
    public var longBlinkMaxDuration: Double
    /// Double-click window in seconds. Range: 0.3...2.0
    public var doubleBlinkWindow: Double
    /// Cooldown between clicks in seconds. Range: 0.2...2.0
    public var blinkCooldown: Double
    /// EAR drop sharpness threshold. Range: 0.02...0.2
    public var blinkSharpness: Double

    // MARK: - Expressions

    /// Per-expression configuration. Uses String keys for reliable Codable round-tripping.
    public var expressionConfigs: [String: ExpressionConfig]
    /// EAR below which an eye is "closed" for wink detection. Range: 0.05...0.3
    public var winkClosedThreshold: Double
    /// EAR above which an eye is "open" for wink detection. Range: 0.1...0.4
    public var winkOpenThreshold: Double

    // MARK: - Gestures

    public var gestureConfig: GestureConfig
    public var handGesturesEnabled: Bool

    // MARK: - HUD

    public var showHUD: Bool
    public var hudExpanded: Bool

    // MARK: - Keyboard

    public var keyboardEnabled: Bool
    /// Key size multiplier. Range: 0.5...2.0
    public var keySize: Double
    public var predictionBarEnabled: Bool

    // MARK: - Head Tilt

    /// Dead zone in degrees before tilt moves cursor. Range: 0...10
    public var headTiltDeadZone: Double
    /// Cursor pixels per degree of head tilt. Range: 0.1...3.0
    public var headTiltPixelsPerDegree: Double

    // MARK: - Init

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

    // MARK: - Expression Config Helpers

    private static var defaultExpressionConfigs: [String: ExpressionConfig] {
        var configs: [String: ExpressionConfig] = [:]
        for (type, config) in ExpressionConfig.defaults {
            configs[type.rawValue] = config
        }
        return configs
    }

    /// Get the config for a specific expression type.
    public func expressionConfig(for type: ExpressionType) -> ExpressionConfig {
        expressionConfigs[type.rawValue] ?? ExpressionConfig.defaults[type]!
    }

    /// Set the config for a specific expression type.
    public mutating func setExpressionConfig(_ config: ExpressionConfig, for type: ExpressionType) {
        expressionConfigs[type.rawValue] = config
        updatedAt = Date()
    }

    /// Reconstruct the typed dictionary for ExpressionDetector.
    public var typedExpressionConfigs: [ExpressionType: ExpressionConfig] {
        var result: [ExpressionType: ExpressionConfig] = [:]
        for type in ExpressionType.allCases {
            result[type] = expressionConfig(for: type)
        }
        return result
    }

    // MARK: - Presets

    public static let `default` = UserProfile()

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
