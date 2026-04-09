# Lucent Phase 5 Design Spec: Settings, Profiles & Onboarding

## Overview

Phase 5 turns Lucent into a polished product with full settings persistence, user profiles, and improved onboarding. Every tunable parameter across the tracking pipeline gets a real UI binding backed by a persistent profile system.

## 1. UserProfile Model

A single `Codable` struct that captures every configurable setting in the app. Stored as JSON in `~/Library/Application Support/Lucent/profiles/`.

```swift
public struct UserProfile: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    // -- General --
    public var launchAtLogin: Bool
    public var autoStartTracking: Bool
    public var pauseOnScreenLock: Bool
    public var selectedCameraID: String?

    // -- Cursor --
    public var cursorSmoothing: Double        // processNoise (1..10, default 2.0)
    public var cursorMeasurementNoise: Double  // measurementNoise (1..20, default 8.0)
    public var dwellRadius: Double             // pixels (10..80, default 30)
    public var dwellTime: Double               // seconds (0.05..1.0, default 0.2)
    public var cursorSpeed: Double             // multiplier (0.5..3.0, default 1.0)

    // -- Click (Blink) --
    public var earThreshold: Double            // (0.1..0.4, default 0.2)
    public var quickBlinkMaxDuration: Double   // seconds (0.1..0.5, default 0.3)
    public var longBlinkMaxDuration: Double    // seconds (0.4..1.5, default 0.8)
    public var doubleBlinkWindow: Double       // seconds (0.3..2.0, default 1.0)
    public var blinkCooldown: Double           // seconds (0.2..2.0, default 0.75)
    public var blinkSharpness: Double          // (0.02..0.2, default 0.08)

    // -- Expressions --
    public var expressionConfigs: [ExpressionType: ExpressionConfig]
    public var winkClosedThreshold: Double     // (0.05..0.3, default 0.15)
    public var winkOpenThreshold: Double       // (0.1..0.4, default 0.22)

    // -- Gestures --
    public var gestureConfig: GestureConfig
    public var handGesturesEnabled: Bool

    // -- HUD --
    public var showHUD: Bool
    public var hudExpanded: Bool

    // -- Keyboard --
    public var keyboardEnabled: Bool
    public var keySize: Double                 // multiplier (0.5..2.0, default 1.0)
    public var predictionBarEnabled: Bool

    // -- Head Tilt --
    public var headTiltDeadZone: Double        // degrees (0..10, default 3.0)
    public var headTiltPixelsPerDegree: Double // (0.1..3.0, default 0.7)

    public static let `default`: UserProfile
}
```

### Defaults

`UserProfile.default` initializes every field to match the current hardcoded defaults across all components (CursorSmoother, BlinkDetector, ExpressionDetector, GestureRecognizer, TapDetector, HeadTiltProcessor).

### Codable Conformance

`ExpressionType` and `ExpressionConfig` are already `Codable`. `GestureConfig` is already `Codable`. The profile serializes cleanly to JSON.

## 2. SettingsManager

Central `@Observable` class that owns the profile lifecycle:

```swift
@MainActor
@Observable
public final class SettingsManager {
    public var currentProfile: UserProfile
    public var availableProfiles: [UserProfile]
    public var activeProfileID: UUID

    // File paths
    private static var profilesDirectory: URL  // ~/Library/Application Support/Lucent/profiles/

    // CRUD
    public func loadProfiles()
    public func saveCurrentProfile()
    public func createProfile(name: String) -> UserProfile
    public func deleteProfile(id: UUID)
    public func switchProfile(to id: UUID)

    // Apply to components
    public func apply(to blinkDetector: BlinkDetector)
    public func apply(to cursorSmoother: CursorSmoother)
    public func apply(to expressionDetector: ExpressionDetector)
    public func apply(to gestureRecognizer: GestureRecognizer)
    public func apply(to tapDetector: TapDetector)
    public func apply(to headTiltProcessor: HeadTiltProcessor)
    public func applyAll(pipeline: TrackingPipeline)
}
```

### Storage

- Profiles stored as `{uuid}.json` files in the profiles directory
- Active profile ID stored in UserDefaults (`activeProfileID`)
- On launch: load all profiles, select active, apply to pipeline
- On change: auto-save with debounce (0.5s)

### Apply Methods

Each `apply` method maps UserProfile fields to the component's mutable properties. For CursorSmoother, which uses `let` properties, the pipeline must create a new instance with updated configuration.

## 3. Component applySettings Methods

Since CursorSmoother uses `let` for configuration, we add a static factory method instead:

```swift
// CursorSmoother
public static func configured(
    dwellRadius: Double,
    dwellTime: Double,
    processNoise: Double,
    measurementNoise: Double
) -> CursorSmoother

// BlinkDetector - already has public vars, apply directly
// ExpressionDetector - already has public var configs, apply directly
// GestureRecognizer - already has public var config, apply directly
// TapDetector - already has public var config, apply directly
// HeadTiltProcessor - already has public vars, apply directly
```

TrackingPipeline needs a method to accept and apply settings:
```swift
public func applySettings(_ profile: UserProfile)
```

## 4. Redesigned SettingsView

8 tabs replacing the current 5-tab view with placeholder bindings:

### Tab 1: General
- Launch at login toggle
- Auto-start tracking toggle
- Pause on screen lock toggle
- Camera picker (AVCaptureDevice list)
- Profile picker (ProfilePickerView embedded)

### Tab 2: Tracking
- Camera selection
- Face detection confidence display
- Baseline frames slider for expression calibration

### Tab 3: Cursor
- Process noise slider ("Smoothing") 
- Measurement noise slider
- Dwell radius slider with value display
- Dwell time slider with value display
- Cursor speed multiplier slider

### Tab 4: Click
- EAR threshold slider
- Quick blink max duration slider
- Long blink max duration slider
- Double blink window slider
- Cooldown duration slider
- Sharpness threshold slider

### Tab 5: Expressions
- Per-expression (winkLeft, winkRight, smile, browRaise, mouthOpen):
  - Enable toggle
  - Hold duration slider
  - Cooldown slider
  - Threshold multiplier slider
- Wink closed/open threshold sliders

### Tab 6: Gestures
- Master enable toggle
- Per-gesture category:
  - Swipe: displacement X/Y, window, cooldown
  - Pinch: threshold
  - Fist: hold duration
  - Point: hold duration
  - Open Palm: hold duration, velocity threshold

### Tab 7: Keyboard
- Enable keyboard mode toggle
- Key size multiplier slider
- Prediction bar enable toggle

### Tab 8: Calibration
- Run Full Calibration button
- Head tilt dead zone slider
- Head tilt pixels per degree slider
- Reset calibration button

All bindings are live -- changing a slider immediately writes to `SettingsManager.currentProfile` and triggers `applyAll`.

## 5. Improved Onboarding (OnboardingView)

6-step wizard replacing FirstLaunchWizard's 4 steps:

1. **Welcome** - App icon, tagline, "Get Started" button
2. **Camera Permission** - Request camera access, show granted status
3. **Accessibility Permission** - Request accessibility, show granted status
4. **Profile Setup** - Choose a name for the profile, pick sensitivity preset (Beginner/Normal/Advanced)
5. **Calibration Prompt** - Explain calibration, offer to start
6. **Complete** - Summary of setup, "Start Using Lucent" button

### Sensitivity Presets
- **Beginner**: Higher smoothing, longer dwell, longer blink thresholds, higher cooldowns
- **Normal**: Default values
- **Advanced**: Lower smoothing, shorter dwell, tighter thresholds, lower cooldowns

## 6. ProfilePickerView

Embedded in the General tab of settings:

```swift
struct ProfilePickerView: View {
    // Shows list of profiles with radio selection
    // "New Profile" button (creates with default settings)
    // "Delete" button (with confirmation, cannot delete last profile)
    // Profile name editing (inline text field)
}
```

## 7. Integration Points

### AppState Changes
- Add `@Published var settingsManager: SettingsManager`
- Remove individual UserDefaults reads for `showHUD`, `hudExpanded`, `handGesturesEnabled`, `keyboardModeEnabled` -- all come from profile now
- `hasCompletedOnboarding` stays in UserDefaults (not profile-specific)

### TrackingPipeline Changes
- Add `applySettings(_ profile: UserProfile)` method
- CursorSmoother recreation on settings change
- BlinkDetector/ExpressionDetector/GestureRecognizer/TapDetector property updates
- HeadTiltProcessor property updates

### Data Flow
```
SettingsView slider change
  -> SettingsManager.currentProfile mutation
  -> SettingsManager.saveCurrentProfile() (debounced)
  -> SettingsManager.applyAll(pipeline:)
  -> Each component updated
```
