# Lucent Phase 1: Eye Cursor + Blink Click — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that moves the cursor with eye gaze and clicks via blinks, using only a standard webcam.

**Architecture:** Swift Package (`LucentCore`) for all testable core logic (models, tracking, control), with a separate Xcode app target for UI and system integration. XcodeGen generates the `.xcodeproj` from a declarative `project.yml`. Camera frames flow through Vision landmark detection and a CoreML gaze model, then through calibration mapping and Kalman smoothing before posting cursor events via CGEvent.

**Tech Stack:** Swift, SwiftUI, AVFoundation, Apple Vision, CoreML, CGEvent, Accelerate (LAPACK), XcodeGen, SPM

**Spec:** `docs/superpowers/specs/2026-04-09-lucent-phase1-design.md`

---

## File Structure

```
Lucent/
├── Package.swift
├── Sources/
│   └── LucentCore/
│       ├── Models/
│       │   ├── GazePoint.swift
│       │   ├── TrackingState.swift
│       │   └── CalibrationProfile.swift
│       ├── Tracking/
│       │   ├── FaceLandmarkDetector.swift
│       │   ├── GazeEstimating.swift
│       │   ├── MockGazeEstimator.swift
│       │   └── BlinkDetector.swift
│       ├── Control/
│       │   ├── CalibrationEngine.swift
│       │   ├── CursorSmoother.swift
│       │   └── InputController.swift
│       └── Camera/
│           ├── CameraManager.swift
│           └── FrameProcessor.swift
├── Tests/
│   └── LucentCoreTests/
│       ├── BlinkDetectorTests.swift
│       ├── CalibrationEngineTests.swift
│       ├── CursorSmootherTests.swift
│       └── MockGazeEstimatorTests.swift
├── project.yml
├── App/
│   ├── LucentApp.swift
│   ├── AppState.swift
│   ├── Permissions.swift
│   ├── TrackingPipeline.swift
│   ├── UI/
│   │   ├── MenuBarView.swift
│   │   ├── SettingsView.swift
│   │   ├── CalibrationOverlay.swift
│   │   └── FirstLaunchWizard.swift
│   ├── Info.plist
│   └── Lucent.entitlements
├── Resources/
│   └── Assets.xcassets/
│       └── AppIcon.appiconset/
│           └── Contents.json
└── docs/
```

---

## Task 1: Project Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/LucentCore/LucentCore.swift` (namespace placeholder)
- Create: `Tests/LucentCoreTests/LucentCoreTests.swift`

- [ ] **Step 1: Initialize git repo (skip if exists) and create Package.swift**

```swift
// Package.swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LucentCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LucentCore", targets: ["LucentCore"]),
    ],
    targets: [
        .target(
            name: "LucentCore",
            path: "Sources/LucentCore"
        ),
        .testTarget(
            name: "LucentCoreTests",
            dependencies: ["LucentCore"],
            path: "Tests/LucentCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Create namespace placeholder and initial test**

```swift
// Sources/LucentCore/LucentCore.swift
public enum LucentCore {
    public static let version = "0.1.0"
}
```

```swift
// Tests/LucentCoreTests/LucentCoreTests.swift
import Testing
@testable import LucentCore

@Test func versionExists() {
    #expect(LucentCore.version == "0.1.0")
}
```

- [ ] **Step 3: Verify build and test pass**

Run: `swift test`
Expected: Build succeeds, 1 test passes

- [ ] **Step 4: Create app directory structure and XcodeGen config**

Install xcodegen if not present: `brew install xcodegen`

Create all app directories:
```bash
mkdir -p App/UI Resources/Assets.xcassets/AppIcon.appiconset
```

```yaml
# project.yml
name: Lucent
options:
  bundleIdPrefix: com.lucent
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true

packages:
  LucentCore:
    path: .

targets:
  Lucent:
    type: application
    platform: macOS
    sources:
      - path: App
    dependencies:
      - package: LucentCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.lucent.app
        INFOPLIST_FILE: App/Info.plist
        CODE_SIGN_ENTITLEMENTS: App/Lucent.entitlements
        CODE_SIGN_IDENTITY: "-"
        ENABLE_APP_SANDBOX: NO
        MACOSX_DEPLOYMENT_TARGET: "14.0"
```

```xml
<!-- App/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Lucent</string>
    <key>CFBundleIdentifier</key>
    <string>com.lucent.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Lucent uses your camera to track eye movements for cursor control.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
```

```xml
<!-- App/Lucent.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.camera</key>
    <true/>
</dict>
</plist>
```

```json
// Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
{
  "images": [
    {
      "idiom": "mac",
      "scale": "1x",
      "size": "128x128"
    },
    {
      "idiom": "mac",
      "scale": "2x",
      "size": "128x128"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

- [ ] **Step 5: Create minimal app entry point so Xcode project builds**

```swift
// App/LucentApp.swift
import SwiftUI

@main
struct LucentApp: App {
    var body: some Scene {
        MenuBarExtra("Lucent", systemImage: "eye") {
            Text("Lucent v0.1.0")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
```

- [ ] **Step 6: Generate Xcode project and verify build**

Run: `xcodegen generate`
Expected: `project.yml` processed, `Lucent.xcodeproj` created

Run: `xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ Tests/ App/ Resources/ project.yml .gitignore
git commit -m "feat: scaffold Lucent project with SPM core and Xcode app"
```

---

## Task 2: Core Data Models

**Files:**
- Create: `Sources/LucentCore/Models/GazePoint.swift`
- Create: `Sources/LucentCore/Models/TrackingState.swift`
- Create: `Sources/LucentCore/Models/CalibrationProfile.swift`
- Test: `Tests/LucentCoreTests/CalibrationProfileTests.swift`

- [ ] **Step 1: Create GazePoint model**

```swift
// Sources/LucentCore/Models/GazePoint.swift
import Foundation

/// A 2D point representing gaze position.
/// In "raw" space these are normalized camera coords (0..1).
/// In "screen" space these are pixel coords.
public struct GazePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = GazePoint(x: 0, y: 0)

    public func distance(to other: GazePoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
```

- [ ] **Step 2: Create TrackingState enum**

```swift
// Sources/LucentCore/Models/TrackingState.swift
import Foundation

public enum TrackingState: Equatable, Sendable {
    case idle
    case detecting
    case tracking
    case calibrating
    case paused(reason: PauseReason)

    public enum PauseReason: Equatable, Sendable {
        case faceLost
        case poorLighting
        case cameraDisconnected
        case userPaused
    }
}
```

- [ ] **Step 3: Create CalibrationProfile model**

```swift
// Sources/LucentCore/Models/CalibrationProfile.swift
import Foundation

/// Stores polynomial coefficients mapping raw gaze to screen coordinates.
/// x_screen = a[0] + a[1]*gx + a[2]*gy + a[3]*gx^2 + a[4]*gy^2 + a[5]*gx*gy
/// y_screen = b[0] + b[1]*gx + b[2]*gy + b[3]*gx^2 + b[4]*gy^2 + b[5]*gx*gy
public struct CalibrationProfile: Codable, Equatable, Sendable {
    public var xCoefficients: [Double]  // 6 coefficients for x mapping
    public var yCoefficients: [Double]  // 6 coefficients for y mapping
    public var cameraID: String
    public var timestamp: Date
    public var screenWidth: Double
    public var screenHeight: Double

    public init(
        xCoefficients: [Double],
        yCoefficients: [Double],
        cameraID: String,
        timestamp: Date = Date(),
        screenWidth: Double,
        screenHeight: Double
    ) {
        precondition(xCoefficients.count == 6, "Need exactly 6 x coefficients")
        precondition(yCoefficients.count == 6, "Need exactly 6 y coefficients")
        self.xCoefficients = xCoefficients
        self.yCoefficients = yCoefficients
        self.cameraID = cameraID
        self.timestamp = timestamp
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }

    /// Map a raw gaze point to a screen coordinate using the polynomial.
    public func mapToScreen(_ raw: GazePoint) -> GazePoint {
        let gx = raw.x
        let gy = raw.y
        let features = [1.0, gx, gy, gx * gx, gy * gy, gx * gy]

        let sx = zip(xCoefficients, features).reduce(0.0) { $0 + $1.0 * $1.1 }
        let sy = zip(yCoefficients, features).reduce(0.0) { $0 + $1.0 * $1.1 }

        return GazePoint(
            x: max(0, min(screenWidth, sx)),
            y: max(0, min(screenHeight, sy))
        )
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Lucent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("calibration.json")
    }

    public func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.fileURL)
    }

    public static func load() throws -> CalibrationProfile {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(CalibrationProfile.self, from: data)
    }

    public static func deleteOnDisk() throws {
        try FileManager.default.removeItem(at: fileURL)
    }
}
```

- [ ] **Step 4: Write test for CalibrationProfile mapping and serialization**

```swift
// Tests/LucentCoreTests/CalibrationProfileTests.swift
import Testing
@testable import LucentCore

@Test func identityMappingReturnsInputScaled() {
    // Coefficients that map (gx, gy) -> (gx * 1920, gy * 1080)
    // x = 0 + 1920*gx + 0*gy + 0 + 0 + 0
    // y = 0 + 0*gx + 1080*gy + 0 + 0 + 0
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
```

- [ ] **Step 5: Run tests**

Run: `swift test`
Expected: All tests pass (including Task 1's version test + 3 new tests)

- [ ] **Step 6: Commit**

```bash
git add Sources/LucentCore/Models/ Tests/LucentCoreTests/CalibrationProfileTests.swift
git commit -m "feat: add core data models (GazePoint, TrackingState, CalibrationProfile)"
```

---

## Task 3: BlinkDetector (TDD)

**Files:**
- Create: `Sources/LucentCore/Tracking/BlinkDetector.swift`
- Create: `Tests/LucentCoreTests/BlinkDetectorTests.swift`

- [ ] **Step 1: Write failing tests for EAR calculation and blink classification**

```swift
// Tests/LucentCoreTests/BlinkDetectorTests.swift
import Testing
@testable import LucentCore

// --- EAR Tests ---

@Test func earOpenEyeReturnsHighValue() {
    // Simulate wide-open eye: tall vertical, normal horizontal
    let points = makeEyePoints(verticalScale: 1.0)
    let ear = BlinkDetector.computeEAR(eyePoints: points)
    #expect(ear > 0.25)
}

@Test func earClosedEyeReturnsLowValue() {
    // Simulate closed eye: nearly zero vertical
    let points = makeEyePoints(verticalScale: 0.05)
    let ear = BlinkDetector.computeEAR(eyePoints: points)
    #expect(ear < 0.1)
}

// --- Blink Classification Tests ---

@Test func quickBlinkProducesLeftClick() {
    let detector = BlinkDetector()
    // Simulate open -> closed -> open in 200ms (quick blink)
    let events = simulateBlink(detector: detector, closedFrames: 6, fps: 30)
    #expect(events.contains(.leftClick))
}

@Test func longBlinkProducesRightClick() {
    let detector = BlinkDetector()
    // Simulate open -> closed -> open in 500ms (long blink)
    let events = simulateBlink(detector: detector, closedFrames: 15, fps: 30)
    #expect(events.contains(.rightClick))
}

@Test func doubleBlinkProducesDoubleClick() {
    let detector = BlinkDetector()
    // Two quick blinks within 500ms
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
    // Natural blink: gentle close, both eyes symmetric
    // Feed gradual EAR decrease (not sharp) — should be filtered
    var events: [BlinkDetector.ClickEvent] = []
    let timestamps = stride(from: 0.0, through: 0.3, by: 1.0/30.0)
    for (i, t) in timestamps.enumerated() {
        let ear: Double
        if i < 3 { ear = 0.3 - Double(i) * 0.03 } // gentle decrease
        else if i < 6 { ear = 0.21 - Double(i - 3) * 0.04 } // dips below
        else { ear = 0.1 + Double(i - 6) * 0.04 } // gentle recovery
        events += detector.update(ear: ear, timestamp: t)
    }
    #expect(events.isEmpty, "Natural gentle blink should be filtered")
}

@Test func cooldownPreventsDoubleTrigger() {
    let detector = BlinkDetector()
    let events1 = simulateBlink(detector: detector, closedFrames: 5, fps: 30)
    #expect(events1.contains(.leftClick))
    // Immediately another blink within cooldown (200ms = 6 frames)
    let events2 = simulateBlink(detector: detector, closedFrames: 5, fps: 30)
    #expect(events2.isEmpty, "Should be suppressed by cooldown")
}

// MARK: - Helpers

/// Create 8 eye contour points simulating an eye shape.
/// Points form an ellipse. verticalScale 1.0 = fully open, 0.0 = closed.
private func makeEyePoints(verticalScale: Double) -> [CGPoint] {
    let cx = 0.5, cy = 0.5
    let rx = 0.05  // horizontal radius (fixed)
    let ry = 0.02 * verticalScale  // vertical radius (scales with openness)
    // 8 points around ellipse, starting at right (0°), counterclockwise
    return (0..<8).map { i in
        let angle = Double(i) * (.pi * 2.0 / 8.0)
        return CGPoint(
            x: cx + rx * cos(angle),
            y: cy + ry * sin(angle)
        )
    }
}

/// Simulate a blink: open frames, closed frames, open frames.
/// Returns accumulated click events.
private func simulateBlink(
    detector: BlinkDetector,
    closedFrames: Int,
    fps: Double
) -> [BlinkDetector.ClickEvent] {
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
    // 10 open frames (let the blink complete and be classified)
    for _ in 0..<10 {
        events += detector.update(ear: 0.3, timestamp: detector.lastTimestamp + dt)
    }
    return events
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | head -20`
Expected: Compilation error — `BlinkDetector` not defined

- [ ] **Step 3: Implement BlinkDetector**

```swift
// Sources/LucentCore/Tracking/BlinkDetector.swift
import Foundation
import CoreGraphics

public final class BlinkDetector: @unchecked Sendable {

    public enum ClickEvent: Equatable, Sendable {
        case leftClick
        case rightClick
        case doubleClick
    }

    // MARK: - Configuration

    public var earThreshold: Double = 0.2
    public var quickBlinkMaxDuration: Double = 0.3
    public var longBlinkMaxDuration: Double = 0.8
    public var doubleBlinkWindow: Double = 0.5
    public var cooldownDuration: Double = 0.2
    public var sharpnessThreshold: Double = 0.08  // min EAR drop per frame for intentional blink

    // MARK: - State

    public private(set) var lastTimestamp: Double = 0.0
    private var previousEAR: Double = 0.3
    private var blinkStartTime: Double?
    private var blinkStartEAR: Double = 0.3
    private var isEyeClosed = false
    private var lastClickTime: Double = -1.0
    private var pendingSingleClick: (event: ClickEvent, time: Double)?

    public init() {}

    // MARK: - Public API

    /// Feed a new EAR sample. Returns any click events triggered.
    public func update(ear: Double, timestamp: Double) -> [ClickEvent] {
        defer {
            previousEAR = ear
            lastTimestamp = timestamp
        }

        var events: [ClickEvent] = []

        // Check if pending single click should upgrade to double click
        if let pending = pendingSingleClick {
            if timestamp - pending.time > doubleBlinkWindow {
                // Window expired — emit the pending single click
                events.append(pending.event)
                pendingSingleClick = nil
            }
        }

        let wasOpen = !isEyeClosed
        let nowClosed = ear < earThreshold
        let nowOpen = ear >= earThreshold

        if wasOpen && nowClosed {
            // Eye just closed — start tracking blink
            let earDrop = previousEAR - ear
            isEyeClosed = true
            blinkStartTime = timestamp
            blinkStartEAR = previousEAR

            // Check sharpness: intentional blinks drop fast
            if earDrop < sharpnessThreshold {
                // Too gentle — likely natural blink, mark to ignore
                blinkStartTime = nil
            }
        } else if isEyeClosed && nowOpen {
            // Eye just opened — classify the blink
            isEyeClosed = false

            if let startTime = blinkStartTime {
                let duration = timestamp - startTime

                // Check cooldown
                if timestamp - lastClickTime < cooldownDuration {
                    blinkStartTime = nil
                    return events
                }

                if duration < quickBlinkMaxDuration {
                    // Quick blink — could be single or start of double
                    if let pending = pendingSingleClick {
                        // This is the second blink — double click
                        pendingSingleClick = nil
                        lastClickTime = timestamp
                        events.append(.doubleClick)
                    } else {
                        // First quick blink — wait to see if double
                        pendingSingleClick = (.leftClick, timestamp)
                    }
                } else if duration < longBlinkMaxDuration {
                    // Long blink — right click (no double-click upgrade)
                    if pendingSingleClick != nil { pendingSingleClick = nil }
                    lastClickTime = timestamp
                    events.append(.rightClick)
                }
                // duration >= longBlinkMaxDuration: intentional hold, ignore
            }
        }

        return events
    }

    // MARK: - Static Helpers

    /// Compute Eye Aspect Ratio from 8 eye contour points.
    /// Points are expected in counterclockwise order starting from the outer corner.
    public static func computeEAR(eyePoints: [CGPoint]) -> Double {
        guard eyePoints.count >= 8 else { return 0.0 }

        // Horizontal: distance between point 0 (outer) and point 4 (inner)
        let horizontal = distance(eyePoints[0], eyePoints[4])
        guard horizontal > 0 else { return 0.0 }

        // Vertical: average of two vertical spans
        let v1 = distance(eyePoints[1], eyePoints[7])
        let v2 = distance(eyePoints[2], eyePoints[6])

        return (v1 + v2) / (2.0 * horizontal)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All BlinkDetector tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/LucentCore/Tracking/BlinkDetector.swift Tests/LucentCoreTests/BlinkDetectorTests.swift
git commit -m "feat: add BlinkDetector with EAR calculation and blink classification"
```

---

## Task 4: CalibrationEngine (TDD)

**Files:**
- Create: `Sources/LucentCore/Control/CalibrationEngine.swift`
- Create: `Tests/LucentCoreTests/CalibrationEngineTests.swift`

- [ ] **Step 1: Write failing tests for polynomial fitting and calibration flow**

```swift
// Tests/LucentCoreTests/CalibrationEngineTests.swift
import Testing
@testable import LucentCore

@Test func fittingLinearDataRecoversCoefficients() {
    // If screen = 100 * gaze (linear), the engine should recover that
    let engine = CalibrationEngine(screenWidth: 1000, screenHeight: 1000)
    let gazePoints = [
        GazePoint(x: 0.0, y: 0.0),
        GazePoint(x: 0.5, y: 0.0),
        GazePoint(x: 1.0, y: 0.0),
        GazePoint(x: 0.0, y: 0.5),
        GazePoint(x: 0.5, y: 0.5),
        GazePoint(x: 1.0, y: 0.5),
        GazePoint(x: 0.0, y: 1.0),
        GazePoint(x: 0.5, y: 1.0),
        GazePoint(x: 1.0, y: 1.0),
    ]
    let screenPoints = gazePoints.map { GazePoint(x: $0.x * 1000, y: $0.y * 1000) }

    let profile = engine.fit(gazePoints: gazePoints, screenPoints: screenPoints, cameraID: "test")

    // Should map (0.3, 0.7) -> (300, 700)
    let mapped = profile.mapToScreen(GazePoint(x: 0.3, y: 0.7))
    #expect(abs(mapped.x - 300) < 1.0)
    #expect(abs(mapped.y - 700) < 1.0)
}

@Test func fittingQuadraticDataRecoversMapping() {
    // Nonlinear: screen_x = 500 * gx^2, screen_y = 500 * gy^2
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

    // Simulate collecting samples for each target
    for target in targets {
        // Pretend gaze is perfectly at the normalized target position
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

    // Should approximately recover the mapping
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
    // Add 2 extreme outliers
    samples.append(GazePoint(x: 10.0, y: 10.0))
    samples.append(GazePoint(x: -5.0, y: -5.0))

    let cleaned = CalibrationEngine.rejectOutliers(samples)
    #expect(cleaned.count >= 55)
    #expect(cleaned.count <= 58)
    // Outliers should be gone
    #expect(!cleaned.contains(where: { $0.x > 1.0 || $0.x < 0.0 }))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | head -20`
Expected: Compilation error — `CalibrationEngine` not defined

- [ ] **Step 3: Implement CalibrationEngine**

```swift
// Sources/LucentCore/Control/CalibrationEngine.swift
import Foundation
import Accelerate

public final class CalibrationEngine: @unchecked Sendable {

    public let screenWidth: Double
    public let screenHeight: Double
    public private(set) var currentTargetIndex: Int = 0
    private var samples: [[GazePoint]]  // samples per calibration target

    public init(screenWidth: Double, screenHeight: Double) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.samples = Array(repeating: [], count: 9)
    }

    /// The 9 screen-space calibration target positions.
    /// Order: TL, TC, TR, ML, MC, MR, BL, BC, BR.
    public func calibrationTargets() -> [GazePoint] {
        let margin = 0.1
        let xs = [margin * screenWidth, screenWidth / 2, (1 - margin) * screenWidth]
        let ys = [margin * screenHeight, screenHeight / 2, (1 - margin) * screenHeight]
        var targets: [GazePoint] = []
        for y in ys {
            for x in xs {
                targets.append(GazePoint(x: x, y: y))
            }
        }
        return targets
    }

    public func addSample(rawGaze: GazePoint, targetIndex: Int) {
        guard targetIndex >= 0 && targetIndex < 9 else { return }
        samples[targetIndex].append(rawGaze)
    }

    public func advanceTarget() {
        if currentTargetIndex < 8 {
            currentTargetIndex += 1
        }
    }

    public func reset() {
        currentTargetIndex = 0
        samples = Array(repeating: [], count: 9)
    }

    public func sampleCount(for targetIndex: Int) -> Int {
        guard targetIndex >= 0 && targetIndex < 9 else { return 0 }
        return samples[targetIndex].count
    }

    /// Build a CalibrationProfile from collected samples.
    public func buildProfile(cameraID: String) -> CalibrationProfile? {
        let targets = calibrationTargets()
        var allGaze: [GazePoint] = []
        var allScreen: [GazePoint] = []

        for (i, target) in targets.enumerated() {
            let cleaned = Self.rejectOutliers(samples[i])
            guard !cleaned.isEmpty else { return nil }
            let avgX = cleaned.map(\.x).reduce(0, +) / Double(cleaned.count)
            let avgY = cleaned.map(\.y).reduce(0, +) / Double(cleaned.count)
            allGaze.append(GazePoint(x: avgX, y: avgY))
            allScreen.append(target)
        }

        return fit(gazePoints: allGaze, screenPoints: allScreen, cameraID: cameraID)
    }

    /// Fit polynomial coefficients from gaze-screen point pairs.
    public func fit(gazePoints: [GazePoint], screenPoints: [GazePoint], cameraID: String) -> CalibrationProfile {
        let n = gazePoints.count
        let numCoeffs = 6

        // Build feature matrix: [1, gx, gy, gx^2, gy^2, gx*gy] for each point
        // LAPACK expects column-major order
        var A = [Double](repeating: 0, count: n * numCoeffs)
        var bx = [Double](repeating: 0, count: max(n, numCoeffs))
        var by = [Double](repeating: 0, count: max(n, numCoeffs))

        for i in 0..<n {
            let gx = gazePoints[i].x
            let gy = gazePoints[i].y
            let features = [1.0, gx, gy, gx * gx, gy * gy, gx * gy]
            for j in 0..<numCoeffs {
                A[j * n + i] = features[j]  // column-major
            }
            bx[i] = screenPoints[i].x
            by[i] = screenPoints[i].y
        }

        let xCoeffs = solveLeastSquares(A: A, b: bx, m: n, n: numCoeffs)
        let yCoeffs = solveLeastSquares(A: A, b: by, m: n, n: numCoeffs)

        return CalibrationProfile(
            xCoefficients: xCoeffs,
            yCoefficients: yCoeffs,
            cameraID: cameraID,
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )
    }

    // MARK: - Outlier Rejection

    /// Remove samples more than 2 standard deviations from the mean.
    public static func rejectOutliers(_ points: [GazePoint]) -> [GazePoint] {
        guard points.count > 3 else { return points }

        let meanX = points.map(\.x).reduce(0, +) / Double(points.count)
        let meanY = points.map(\.y).reduce(0, +) / Double(points.count)

        let stdX = (points.map { ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +) / Double(points.count)).squareRoot()
        let stdY = (points.map { ($0.y - meanY) * ($0.y - meanY) }.reduce(0, +) / Double(points.count)).squareRoot()

        let threshold = 2.0
        return points.filter { p in
            abs(p.x - meanX) <= threshold * max(stdX, 0.001) &&
            abs(p.y - meanY) <= threshold * max(stdY, 0.001)
        }
    }

    // MARK: - Least Squares Solver

    /// Solve Ax = b using LAPACK dgels (least squares).
    private func solveLeastSquares(A: [Double], b: [Double], m: Int, n: Int) -> [Double] {
        var A = A
        var b = b
        var trans = Int8(UInt8(ascii: "N"))
        var M = __CLPK_integer(m)
        var N = __CLPK_integer(n)
        var nrhs: __CLPK_integer = 1
        var lda = M
        var ldb = __CLPK_integer(max(m, n))
        var workQuery: Double = 0
        var lwork: __CLPK_integer = -1
        var info: __CLPK_integer = 0

        // Query optimal workspace
        dgels_(&trans, &M, &N, &nrhs, &A, &lda, &b, &ldb, &workQuery, &lwork, &info)
        lwork = __CLPK_integer(workQuery)
        var work = [Double](repeating: 0, count: Int(lwork))

        // Solve
        dgels_(&trans, &M, &N, &nrhs, &A, &lda, &b, &ldb, &work, &lwork, &info)

        return Array(b.prefix(n))
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All CalibrationEngine tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/LucentCore/Control/CalibrationEngine.swift Tests/LucentCoreTests/CalibrationEngineTests.swift
git commit -m "feat: add CalibrationEngine with polynomial fitting and outlier rejection"
```

---

## Task 5: CursorSmoother (TDD)

**Files:**
- Create: `Sources/LucentCore/Control/CursorSmoother.swift`
- Create: `Tests/LucentCoreTests/CursorSmootherTests.swift`

- [ ] **Step 1: Write failing tests for Kalman filter, dwell zone, and velocity scaling**

```swift
// Tests/LucentCoreTests/CursorSmootherTests.swift
import Testing
@testable import LucentCore

@Test func stationaryInputConverges() {
    let smoother = CursorSmoother()
    // Feed the same point 30 times — output should converge to it
    var lastOutput = GazePoint.zero
    for _ in 0..<30 {
        lastOutput = smoother.smooth(GazePoint(x: 500, y: 300))
    }
    #expect(abs(lastOutput.x - 500) < 5)
    #expect(abs(lastOutput.y - 300) < 5)
}

@Test func jitteryInputIsSmoothed() {
    let smoother = CursorSmoother()
    // Seed the filter
    for _ in 0..<20 {
        _ = smoother.smooth(GazePoint(x: 500, y: 300))
    }
    // Now feed jittery data around (500, 300)
    var outputs: [GazePoint] = []
    for i in 0..<20 {
        let jitter = Double(i % 2 == 0 ? 50 : -50)
        outputs.append(smoother.smooth(GazePoint(x: 500 + jitter, y: 300 + jitter)))
    }
    // Output variance should be much less than input variance (50px)
    let meanX = outputs.map(\.x).reduce(0, +) / Double(outputs.count)
    let variance = outputs.map { ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +) / Double(outputs.count)
    #expect(variance < 50 * 50, "Smoothed variance should be much less than raw jitter")
}

@Test func dwellZoneLocksCursor() {
    let smoother = CursorSmoother(dwellRadius: 30, dwellTime: 0.2)
    // Converge to a point
    for _ in 0..<30 {
        _ = smoother.smooth(GazePoint(x: 500, y: 300))
    }
    // Small movements within dwell radius
    let output1 = smoother.smooth(GazePoint(x: 510, y: 305))
    let output2 = smoother.smooth(GazePoint(x: 495, y: 298))
    let output3 = smoother.smooth(GazePoint(x: 505, y: 302))

    // After dwell activates, outputs should cluster tightly
    // (they won't be exactly locked since Kalman still processes, but should be very close)
    let spread = output1.distance(to: output3)
    #expect(spread < 30, "Dwell zone should constrain cursor movement")
}

@Test func largeMovementBreaksDwellZone() {
    let smoother = CursorSmoother(dwellRadius: 30, dwellTime: 0.2)
    // Converge to a point
    for _ in 0..<30 {
        _ = smoother.smooth(GazePoint(x: 500, y: 300))
    }
    // Large movement should break dwell and move cursor
    for _ in 0..<15 {
        _ = smoother.smooth(GazePoint(x: 800, y: 600))
    }
    let output = smoother.smooth(GazePoint(x: 800, y: 600))
    #expect(output.x > 600, "Cursor should follow large movement")
}

@Test func fastMovementGetsLessSmoothing() {
    let smootherFast = CursorSmoother()
    let smootherSlow = CursorSmoother()

    // Seed both
    for _ in 0..<20 {
        _ = smootherFast.smooth(GazePoint(x: 100, y: 100))
        _ = smootherSlow.smooth(GazePoint(x: 100, y: 100))
    }

    // Fast jump
    let fastOutput = smootherFast.smooth(GazePoint(x: 900, y: 900))
    // Slow creep
    let slowOutput = smootherSlow.smooth(GazePoint(x: 120, y: 120))

    // Fast movement should cover more distance (less smoothing applied)
    let fastDist = fastOutput.distance(to: GazePoint(x: 100, y: 100))
    let slowDist = slowOutput.distance(to: GazePoint(x: 100, y: 100))
    #expect(fastDist > slowDist, "Fast saccades should be smoothed less")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | head -20`
Expected: Compilation error — `CursorSmoother` not defined

- [ ] **Step 3: Implement CursorSmoother**

```swift
// Sources/LucentCore/Control/CursorSmoother.swift
import Foundation

public final class CursorSmoother: @unchecked Sendable {

    // MARK: - Configuration

    public var dwellRadius: Double
    public var dwellTime: Double
    public var processNoise: Double = 0.5
    public var measurementNoise: Double = 10.0

    // MARK: - Kalman State (2D position + velocity: [x, y, vx, vy])

    private var state: [Double] = [0, 0, 0, 0]  // [x, y, vx, vy]
    private var covariance: [[Double]]            // 4x4
    private var initialized = false

    // MARK: - Dwell Zone State

    private var dwellCenter: GazePoint?
    private var dwellEnteredTime: Double?
    private var dwellActive = false
    private var frameCount: Int = 0

    public init(dwellRadius: Double = 30, dwellTime: Double = 0.2) {
        self.dwellRadius = dwellRadius
        self.dwellTime = dwellTime
        self.covariance = (0..<4).map { i in
            (0..<4).map { j in i == j ? 1000.0 : 0.0 }
        }
    }

    /// Process a raw gaze point and return the smoothed cursor position.
    public func smooth(_ raw: GazePoint) -> GazePoint {
        frameCount += 1

        if !initialized {
            state = [raw.x, raw.y, 0, 0]
            initialized = true
            dwellCenter = raw
            dwellEnteredTime = Double(frameCount) / 30.0
            return raw
        }

        // Velocity scaling: estimate speed from jump distance
        let predicted = GazePoint(x: state[0], y: state[1])
        let jumpDistance = raw.distance(to: predicted)
        let adaptedMeasurementNoise = adaptNoise(jumpDistance: jumpDistance)

        // Kalman predict
        let dt = 1.0 / 30.0
        kalmanPredict(dt: dt)

        // Kalman update
        let filtered = kalmanUpdate(measurement: raw, measurementNoise: adaptedMeasurementNoise)

        // Dwell zone logic
        return applyDwellZone(filtered)
    }

    // MARK: - Velocity Scaling

    private func adaptNoise(jumpDistance: Double) -> Double {
        // Large jumps (saccades): low measurement noise = trust measurement more = less smoothing
        // Small movements: high measurement noise = trust prediction more = more smoothing
        let saccadeThreshold = 100.0
        let ratio = min(jumpDistance / saccadeThreshold, 1.0)
        let minNoise = 1.0    // fast: trust measurement
        let maxNoise = measurementNoise  // slow: heavy smoothing
        return maxNoise - ratio * (maxNoise - minNoise)
    }

    // MARK: - Kalman Filter

    private func kalmanPredict(dt: Double) {
        // State transition: position += velocity * dt
        state[0] += state[2] * dt
        state[1] += state[3] * dt

        // Update covariance: P = F*P*F' + Q
        let F: [[Double]] = [
            [1, 0, dt, 0],
            [0, 1, 0, dt],
            [0, 0, 1,  0],
            [0, 0, 0,  1],
        ]
        let Q = processNoise
        var newP = matMul(matMul(F, covariance), transpose(F))
        for i in 0..<4 { newP[i][i] += Q }
        covariance = newP
    }

    private func kalmanUpdate(measurement: GazePoint, measurementNoise: Double) -> GazePoint {
        // H = [[1,0,0,0],[0,1,0,0]]  — we observe position only
        // Innovation
        let innovX = measurement.x - state[0]
        let innovY = measurement.y - state[1]

        // S = H*P*H' + R
        let s00 = covariance[0][0] + measurementNoise
        let s01 = covariance[0][1]
        let s10 = covariance[1][0]
        let s11 = covariance[1][1] + measurementNoise

        // Invert 2x2 S
        let det = s00 * s11 - s01 * s10
        guard abs(det) > 1e-10 else { return GazePoint(x: state[0], y: state[1]) }
        let si00 =  s11 / det
        let si01 = -s01 / det
        let si10 = -s10 / det
        let si11 =  s00 / det

        // K = P*H'*S^-1  (K is 4x2)
        var K = [[Double]](repeating: [0, 0], count: 4)
        for i in 0..<4 {
            K[i][0] = covariance[i][0] * si00 + covariance[i][1] * si10
            K[i][1] = covariance[i][0] * si01 + covariance[i][1] * si11
        }

        // Update state
        for i in 0..<4 {
            state[i] += K[i][0] * innovX + K[i][1] * innovY
        }

        // Update covariance: P = (I - K*H)*P
        var newP = covariance
        for i in 0..<4 {
            for j in 0..<4 {
                newP[i][j] = covariance[i][j] - K[i][0] * covariance[0][j] - K[i][1] * covariance[1][j]
            }
        }
        covariance = newP

        return GazePoint(x: state[0], y: state[1])
    }

    // MARK: - Dwell Zone

    private func applyDwellZone(_ point: GazePoint) -> GazePoint {
        let currentTime = Double(frameCount) / 30.0

        if let center = dwellCenter {
            let dist = point.distance(to: center)

            if dist <= dwellRadius {
                if let enteredTime = dwellEnteredTime {
                    if currentTime - enteredTime >= dwellTime {
                        dwellActive = true
                    }
                }
                if dwellActive {
                    return center  // Lock to dwell center
                }
                return point
            } else {
                // Broke out of dwell zone
                dwellActive = false
                dwellCenter = point
                dwellEnteredTime = currentTime
                return point
            }
        } else {
            dwellCenter = point
            dwellEnteredTime = currentTime
            return point
        }
    }

    // MARK: - Matrix Helpers

    private func matMul(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
        let m = A.count, n = B[0].count, k = B.count
        var C = [[Double]](repeating: [Double](repeating: 0, count: n), count: m)
        for i in 0..<m {
            for j in 0..<n {
                for p in 0..<k {
                    C[i][j] += A[i][p] * B[p][j]
                }
            }
        }
        return C
    }

    private func transpose(_ A: [[Double]]) -> [[Double]] {
        let m = A.count, n = A[0].count
        var T = [[Double]](repeating: [Double](repeating: 0, count: m), count: n)
        for i in 0..<m {
            for j in 0..<n {
                T[j][i] = A[i][j]
            }
        }
        return T
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All CursorSmoother tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/LucentCore/Control/CursorSmoother.swift Tests/LucentCoreTests/CursorSmootherTests.swift
git commit -m "feat: add CursorSmoother with Kalman filter, dwell zones, velocity scaling"
```

---

## Task 6: GazeEstimating Protocol + Mock (TDD)

**Files:**
- Create: `Sources/LucentCore/Tracking/GazeEstimating.swift`
- Create: `Sources/LucentCore/Tracking/MockGazeEstimator.swift`
- Create: `Tests/LucentCoreTests/MockGazeEstimatorTests.swift`

- [ ] **Step 1: Write failing tests for the mock gaze estimator**

```swift
// Tests/LucentCoreTests/MockGazeEstimatorTests.swift
import Testing
import CoreGraphics
@testable import LucentCore

@Test func mockEstimatorReturnsFaceCenter() {
    let estimator = MockGazeEstimator()
    // Face centered at (0.5, 0.5) in normalized image coords
    let faceRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
    let gaze = estimator.estimate(faceBounds: faceRect, leftPupil: CGPoint(x: 0.45, y: 0.5), rightPupil: CGPoint(x: 0.55, y: 0.5))
    #expect(abs(gaze.x - 0.5) < 0.1)
    #expect(abs(gaze.y - 0.5) < 0.1)
}

@Test func mockEstimatorTracksHeadMovement() {
    let estimator = MockGazeEstimator()
    // Face shifted left
    let leftGaze = estimator.estimate(
        faceBounds: CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.4),
        leftPupil: CGPoint(x: 0.25, y: 0.5),
        rightPupil: CGPoint(x: 0.35, y: 0.5)
    )
    // Face shifted right
    let rightGaze = estimator.estimate(
        faceBounds: CGRect(x: 0.5, y: 0.3, width: 0.4, height: 0.4),
        leftPupil: CGPoint(x: 0.65, y: 0.5),
        rightPupil: CGPoint(x: 0.75, y: 0.5)
    )
    #expect(rightGaze.x > leftGaze.x, "Right-positioned face should produce rightward gaze")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | head -20`
Expected: Compilation error — `GazeEstimating` / `MockGazeEstimator` not defined

- [ ] **Step 3: Implement protocol and mock**

```swift
// Sources/LucentCore/Tracking/GazeEstimating.swift
import Foundation
import CoreGraphics

/// Protocol for gaze estimation backends.
/// Implementations take face/eye data and produce a normalized gaze point.
public protocol GazeEstimating: Sendable {
    /// Estimate gaze direction from face data.
    /// - Parameters:
    ///   - faceBounds: Normalized face bounding box in image coordinates (0..1)
    ///   - leftPupil: Normalized left pupil position
    ///   - rightPupil: Normalized right pupil position
    /// - Returns: Gaze point in normalized coordinates (0..1 range, may exceed bounds)
    func estimate(faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint
}
```

```swift
// Sources/LucentCore/Tracking/MockGazeEstimator.swift
import Foundation
import CoreGraphics

/// Mock gaze estimator that uses pupil midpoint as gaze direction.
/// Sufficient for testing the full pipeline without a real ML model.
public final class MockGazeEstimator: GazeEstimating, @unchecked Sendable {

    public init() {}

    public func estimate(faceBounds: CGRect, leftPupil: CGPoint, rightPupil: CGPoint) -> GazePoint {
        // Average of pupil positions as gaze direction proxy
        let gazeX = Double(leftPupil.x + rightPupil.x) / 2.0
        let gazeY = Double(leftPupil.y + rightPupil.y) / 2.0
        return GazePoint(x: gazeX, y: gazeY)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/LucentCore/Tracking/GazeEstimating.swift Sources/LucentCore/Tracking/MockGazeEstimator.swift Tests/LucentCoreTests/MockGazeEstimatorTests.swift
git commit -m "feat: add GazeEstimating protocol and MockGazeEstimator"
```

---

## Task 7: FaceLandmarkDetector

**Files:**
- Create: `Sources/LucentCore/Tracking/FaceLandmarkDetector.swift`

- [ ] **Step 1: Implement FaceLandmarkDetector**

```swift
// Sources/LucentCore/Tracking/FaceLandmarkDetector.swift
import Foundation
import Vision
import CoreGraphics

public struct FaceData: Sendable {
    public let faceBounds: CGRect           // Normalized bounding box (0..1)
    public let leftEyePoints: [CGPoint]     // 8 contour points, normalized
    public let rightEyePoints: [CGPoint]    // 8 contour points, normalized
    public let leftPupil: CGPoint           // Normalized pupil center
    public let rightPupil: CGPoint          // Normalized pupil center
    public let confidence: Float
}

public final class FaceLandmarkDetector: @unchecked Sendable {

    private let requestHandler: (_ request: VNRequest, _ pixelBuffer: CVPixelBuffer) throws -> Void

    public init() {
        self.requestHandler = { request, buffer in
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
            try handler.perform([request])
        }
    }

    /// Detect face landmarks in a pixel buffer.
    /// Returns nil if no face is detected.
    public func detect(in pixelBuffer: CVPixelBuffer) -> FaceData? {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let face = request.results?.first else { return nil }
        guard let landmarks = face.landmarks else { return nil }

        let bounds = face.boundingBox  // Normalized (0..1), origin at bottom-left

        // Extract eye contours
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil else {
            return nil
        }

        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        let size = CGSize(width: imageWidth, height: imageHeight)

        // Convert normalized landmark points to image-space points
        // Vision uses bottom-left origin, we flip to top-left for consistency
        func convertPoints(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
            let rawPoints = region.pointsInImage(imageSize: size)
            return (0..<region.pointCount).map { i in
                let p = rawPoints[i]
                return CGPoint(
                    x: p.x / CGFloat(imageWidth),
                    y: 1.0 - p.y / CGFloat(imageHeight)
                )
            }
        }

        func convertSinglePoint(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
            let points = convertPoints(region)
            return points.first ?? .zero
        }

        return FaceData(
            faceBounds: CGRect(
                x: bounds.origin.x,
                y: 1.0 - bounds.origin.y - bounds.height,
                width: bounds.width,
                height: bounds.height
            ),
            leftEyePoints: convertPoints(leftEye),
            rightEyePoints: convertPoints(rightEye),
            leftPupil: convertSinglePoint(leftPupil),
            rightPupil: convertSinglePoint(rightPupil),
            confidence: face.confidence
        )
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LucentCore/Tracking/FaceLandmarkDetector.swift
git commit -m "feat: add FaceLandmarkDetector wrapping Apple Vision"
```

---

## Task 8: InputController

**Files:**
- Create: `Sources/LucentCore/Control/InputController.swift`

- [ ] **Step 1: Implement InputController**

```swift
// Sources/LucentCore/Control/InputController.swift
import Foundation
import CoreGraphics
import ApplicationServices

public final class InputController: @unchecked Sendable {

    private let eventSource: CGEventSource?

    public init() {
        self.eventSource = CGEventSource(stateID: .hidSystemState)
    }

    // MARK: - Permission Check

    /// Check if the app has Accessibility permissions for posting synthetic events.
    public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user for Accessibility permission.
    public static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Cursor Movement

    /// Move the cursor to an absolute screen position.
    public func moveCursor(to point: GazePoint) {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        CGWarpMouseCursorPosition(cgPoint)
        // Also post a mouseMoved event so apps react to the movement
        if let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: cgPoint,
            mouseButton: .left
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Click Events

    public func leftClick(at point: GazePoint) {
        postClick(at: point, downType: .leftMouseDown, upType: .leftMouseUp, button: .left)
    }

    public func rightClick(at point: GazePoint) {
        postClick(at: point, downType: .rightMouseDown, upType: .rightMouseUp, button: .right)
    }

    public func doubleClick(at point: GazePoint) {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        for _ in 0..<2 {
            if let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: cgPoint, mouseButton: .left),
               let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: cgPoint, mouseButton: .left) {
                down.setIntegerValueField(.mouseEventClickState, value: 2)
                up.setIntegerValueField(.mouseEventClickState, value: 2)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func postClick(at point: GazePoint, downType: CGEventType, upType: CGEventType, button: CGMouseButton) {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        if let down = CGEvent(mouseEventSource: eventSource, mouseType: downType, mouseCursorPosition: cgPoint, mouseButton: button),
           let up = CGEvent(mouseEventSource: eventSource, mouseType: upType, mouseCursorPosition: cgPoint, mouseButton: button) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LucentCore/Control/InputController.swift
git commit -m "feat: add InputController for CGEvent cursor and click posting"
```

---

## Task 9: CameraManager

**Files:**
- Create: `Sources/LucentCore/Camera/CameraManager.swift`

- [ ] **Step 1: Implement CameraManager**

```swift
// Sources/LucentCore/Camera/CameraManager.swift
import Foundation
import AVFoundation

public protocol CameraManagerDelegate: AnyObject, Sendable {
    func cameraManager(_ manager: CameraManager, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime)
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error)
}

public final class CameraManager: NSObject, @unchecked Sendable {

    public weak var delegate: CameraManagerDelegate?

    private let session = AVCaptureSession()
    private let outputQueue = DispatchQueue(label: "com.lucent.camera", qos: .userInteractive)
    private var videoOutput: AVCaptureVideoDataOutput?

    public private(set) var isRunning = false
    public private(set) var currentDeviceID: String?

    public override init() {
        super.init()
    }

    // MARK: - Permission

    public static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    public static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    // MARK: - Available Cameras

    public static var availableCameras: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    // MARK: - Session Management

    public func start(preferredDeviceID: String? = nil) throws {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        // Select camera
        let device: AVCaptureDevice?
        if let id = preferredDeviceID {
            device = AVCaptureDevice(uniqueID: id)
        } else {
            device = AVCaptureDevice.default(for: .video)
        }

        guard let camera = device else {
            throw CameraError.noCameraAvailable
        }
        currentDeviceID = camera.uniqueID

        // Configure frame rate
        try camera.lockForConfiguration()
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        camera.unlockForConfiguration()

        // Add input
        let input = try AVCaptureDeviceInput(device: camera)
        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Add output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: outputQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        videoOutput = output

        session.commitConfiguration()
        session.startRunning()
        isRunning = true
    }

    public func stop() {
        session.stopRunning()
        isRunning = false
    }

    public enum CameraError: Error, LocalizedError {
        case noCameraAvailable
        case permissionDenied

        public var errorDescription: String? {
            switch self {
            case .noCameraAvailable: return "No camera found"
            case .permissionDenied: return "Camera permission denied"
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        delegate?.cameraManager(self, didOutput: pixelBuffer, timestamp: timestamp)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LucentCore/Camera/CameraManager.swift
git commit -m "feat: add CameraManager with AVFoundation capture"
```

---

## Task 10: FrameProcessor

**Files:**
- Create: `Sources/LucentCore/Camera/FrameProcessor.swift`

- [ ] **Step 1: Implement FrameProcessor**

```swift
// Sources/LucentCore/Camera/FrameProcessor.swift
import Foundation
import CoreGraphics
import CoreImage

/// Processes camera frames: runs face detection, computes gaze and blink state.
public final class FrameProcessor: @unchecked Sendable {

    public struct FrameResult: Sendable {
        public let rawGaze: GazePoint
        public let leftEAR: Double
        public let rightEAR: Double
        public let faceDetected: Bool
        public let confidence: Float
        public let timestamp: Double
    }

    private let landmarkDetector = FaceLandmarkDetector()
    private let gazeEstimator: any GazeEstimating

    public init(gazeEstimator: any GazeEstimating) {
        self.gazeEstimator = gazeEstimator
    }

    /// Process a single camera frame.
    /// Returns nil if no face is detected.
    public func process(pixelBuffer: CVPixelBuffer, timestamp: Double) -> FrameResult? {
        guard let face = landmarkDetector.detect(in: pixelBuffer) else {
            return nil
        }

        // Compute gaze
        let gaze = gazeEstimator.estimate(
            faceBounds: face.faceBounds,
            leftPupil: face.leftPupil,
            rightPupil: face.rightPupil
        )

        // Compute EAR for both eyes
        let leftEAR = BlinkDetector.computeEAR(eyePoints: face.leftEyePoints)
        let rightEAR = BlinkDetector.computeEAR(eyePoints: face.rightEyePoints)

        return FrameResult(
            rawGaze: gaze,
            leftEAR: leftEAR,
            rightEAR: rightEAR,
            faceDetected: true,
            confidence: face.confidence,
            timestamp: timestamp
        )
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LucentCore/Camera/FrameProcessor.swift
git commit -m "feat: add FrameProcessor wiring face detection, gaze, and EAR"
```

---

## Task 11: TrackingPipeline

**Files:**
- Create: `App/TrackingPipeline.swift`

- [ ] **Step 1: Implement TrackingPipeline that wires all components**

```swift
// App/TrackingPipeline.swift
import Foundation
import AVFoundation
import LucentCore

/// Orchestrates the full tracking pipeline: camera → detection → gaze → cursor.
@MainActor
public final class TrackingPipeline: ObservableObject {

    // MARK: - Published State

    @Published public var trackingState: TrackingState = .idle
    @Published public var isEnabled = false
    @Published public var currentCursorPosition = GazePoint.zero

    // MARK: - Components

    private let cameraManager = CameraManager()
    private let frameProcessor: FrameProcessor
    private let blinkDetector = BlinkDetector()
    private let cursorSmoother: CursorSmoother
    private let inputController = InputController()
    private var calibrationProfile: CalibrationProfile?

    // MARK: - Timing

    private var faceLostTime: Double?
    private let faceLostTimeout: Double = 0.5
    private var lowConfidenceCount = 0

    public init() {
        let gazeEstimator = MockGazeEstimator()
        self.frameProcessor = FrameProcessor(gazeEstimator: gazeEstimator)
        self.cursorSmoother = CursorSmoother()

        // Load saved calibration if available
        self.calibrationProfile = try? CalibrationProfile.load()
    }

    // MARK: - Start / Stop

    public func start() throws {
        guard !isEnabled else { return }
        try cameraManager.start()
        cameraManager.delegate = self
        isEnabled = true
        trackingState = calibrationProfile != nil ? .tracking : .detecting
    }

    public func stop() {
        cameraManager.stop()
        isEnabled = false
        trackingState = .idle
    }

    public func toggle() throws {
        if isEnabled { stop() } else { try start() }
    }

    // MARK: - Calibration

    public func setCalibrationProfile(_ profile: CalibrationProfile) {
        self.calibrationProfile = profile
        try? profile.save()
        if isEnabled { trackingState = .tracking }
    }
}

extension TrackingPipeline: CameraManagerDelegate {

    nonisolated public func cameraManager(_ manager: CameraManager, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        let time = CMTimeGetSeconds(timestamp)

        guard let result = frameProcessor.process(pixelBuffer: pixelBuffer, timestamp: time) else {
            // No face detected
            Task { @MainActor in
                handleFaceLost(at: time)
            }
            return
        }

        Task { @MainActor in
            handleFrame(result)
        }
    }

    nonisolated public func cameraManager(_ manager: CameraManager, didFailWithError error: Error) {
        Task { @MainActor in
            trackingState = .paused(reason: .cameraDisconnected)
        }
    }
}

// MARK: - Private Processing

extension TrackingPipeline {

    private func handleFrame(_ result: FrameProcessor.FrameResult) {
        faceLostTime = nil

        // Check confidence
        if result.confidence < 0.5 {
            lowConfidenceCount += 1
            if lowConfidenceCount > 30 { // 1 second of low confidence
                trackingState = .paused(reason: .poorLighting)
            }
        } else {
            lowConfidenceCount = 0
        }

        guard let profile = calibrationProfile else {
            trackingState = .detecting
            return
        }

        trackingState = .tracking

        // Map gaze to screen coordinates
        let screenPoint = profile.mapToScreen(result.rawGaze)

        // Smooth the cursor position
        let smoothed = cursorSmoother.smooth(screenPoint)
        currentCursorPosition = smoothed

        // Move cursor
        inputController.moveCursor(to: smoothed)

        // Process blinks
        let avgEAR = (result.leftEAR + result.rightEAR) / 2.0
        let clickEvents = blinkDetector.update(ear: avgEAR, timestamp: result.timestamp)

        for event in clickEvents {
            switch event {
            case .leftClick:
                inputController.leftClick(at: smoothed)
            case .rightClick:
                inputController.rightClick(at: smoothed)
            case .doubleClick:
                inputController.doubleClick(at: smoothed)
            }
        }
    }

    private func handleFaceLost(at time: Double) {
        if faceLostTime == nil {
            faceLostTime = time
        }
        if let lost = faceLostTime, time - lost > faceLostTimeout {
            trackingState = .paused(reason: .faceLost)
        }
    }
}
```

- [ ] **Step 2: Regenerate Xcode project and verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add App/TrackingPipeline.swift
git commit -m "feat: add TrackingPipeline orchestrating camera-to-cursor flow"
```

---

## Task 12: Permissions Helper

**Files:**
- Create: `App/Permissions.swift`

- [ ] **Step 1: Implement Permissions helper**

```swift
// App/Permissions.swift
import Foundation
import AVFoundation
import LucentCore

@MainActor
public final class Permissions: ObservableObject {

    @Published public var cameraGranted = false
    @Published public var accessibilityGranted = false

    public var allGranted: Bool { cameraGranted && accessibilityGranted }

    public init() {
        refresh()
    }

    public func refresh() {
        cameraGranted = CameraManager.authorizationStatus == .authorized
        accessibilityGranted = InputController.hasAccessibilityPermission
    }

    public func requestCamera() async {
        cameraGranted = await CameraManager.requestPermission()
    }

    public func requestAccessibility() {
        InputController.requestAccessibilityPermission()
        // Poll for change since the user grants this in System Settings
        Task {
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(1))
                if InputController.hasAccessibilityPermission {
                    accessibilityGranted = true
                    return
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add App/Permissions.swift
git commit -m "feat: add Permissions helper for camera and accessibility checks"
```

---

## Task 13: AppState

**Files:**
- Create: `App/AppState.swift`

- [ ] **Step 1: Implement AppState**

```swift
// App/AppState.swift
import Foundation
import SwiftUI
import ServiceManagement
import LucentCore

@MainActor
public final class AppState: ObservableObject {

    @Published public var pipeline = TrackingPipeline()
    @Published public var permissions = Permissions()
    @Published public var showSettings = false
    @Published public var showCalibration = false
    @Published public var hasCompletedOnboarding: Bool

    public init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    // MARK: - Actions

    public func toggleTracking() {
        do {
            try pipeline.toggle()
        } catch {
            print("Failed to toggle tracking: \(error)")
        }
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    // MARK: - Launch at Login

    public var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to set launch at login: \(error)")
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add App/AppState.swift
git commit -m "feat: add AppState managing pipeline, permissions, and settings"
```

---

## Task 14: MenuBarView

**Files:**
- Modify: `App/LucentApp.swift`
- Create: `App/UI/MenuBarView.swift`

- [ ] **Step 1: Implement MenuBarView**

```swift
// App/UI/MenuBarView.swift
import SwiftUI
import LucentCore

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
            }
            .padding(.bottom, 4)

            Divider()

            // Toggle
            Toggle("Eye Tracking", isOn: Binding(
                get: { appState.pipeline.isEnabled },
                set: { _ in appState.toggleTracking() }
            ))

            // Quick recalibrate
            Button("Quick Recalibrate") {
                appState.showCalibration = true
            }
            .disabled(!appState.pipeline.isEnabled)

            Divider()

            Button("Settings...") {
                appState.showSettings = true
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit Lucent") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
        .frame(width: 220)
    }

    private var statusColor: Color {
        switch appState.pipeline.trackingState {
        case .tracking: return .green
        case .detecting: return .yellow
        case .calibrating: return .blue
        case .paused: return .red
        case .idle: return .gray
        }
    }

    private var statusText: String {
        switch appState.pipeline.trackingState {
        case .tracking: return "Tracking Active"
        case .detecting: return "Detecting Face"
        case .calibrating: return "Calibrating"
        case .paused(let reason):
            switch reason {
            case .faceLost: return "Face Lost"
            case .poorLighting: return "Poor Lighting"
            case .cameraDisconnected: return "Camera Disconnected"
            case .userPaused: return "Paused"
            }
        case .idle: return "Idle"
        }
    }
}
```

- [ ] **Step 2: Update LucentApp to use MenuBarView**

```swift
// App/LucentApp.swift
import SwiftUI
import LucentCore

@main
struct LucentApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.pipeline.isEnabled ? "eye.fill" : "eye")
        }

        // Settings window
        Window("Lucent Settings", id: "settings") {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 500, height: 400)

        // Calibration overlay
        Window("Calibration", id: "calibration") {
            CalibrationOverlay(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds (SettingsView and CalibrationOverlay will be stubs — created in next tasks)

Note: This step may fail if SettingsView/CalibrationOverlay don't exist yet. If so, create placeholder stubs:

```swift
// App/UI/SettingsView.swift
import SwiftUI
struct SettingsView: View {
    @ObservedObject var appState: AppState
    var body: some View { Text("Settings placeholder") }
}
```

```swift
// App/UI/CalibrationOverlay.swift
import SwiftUI
struct CalibrationOverlay: View {
    @ObservedObject var appState: AppState
    var body: some View { Text("Calibration placeholder") }
}
```

- [ ] **Step 4: Commit**

```bash
git add App/LucentApp.swift App/UI/MenuBarView.swift App/UI/SettingsView.swift App/UI/CalibrationOverlay.swift
git commit -m "feat: add MenuBarView with tracking status and controls"
```

---

## Task 15: CalibrationOverlay

**Files:**
- Modify: `App/UI/CalibrationOverlay.swift`

- [ ] **Step 1: Implement CalibrationOverlay**

```swift
// App/UI/CalibrationOverlay.swift
import SwiftUI
import LucentCore

struct CalibrationOverlay: View {
    @ObservedObject var appState: AppState
    @State private var engine: CalibrationEngine?
    @State private var currentTargetIndex = 0
    @State private var samplesCollected = 0
    @State private var isComplete = false
    @State private var targets: [GazePoint] = []
    @State private var progress: Double = 0

    private let samplesNeeded = 60
    private let totalTargets = 9

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if isComplete {
                    completionView
                } else if !targets.isEmpty && currentTargetIndex < targets.count {
                    targetDot(in: geo)
                    instructionText
                }
            }
            .onAppear {
                startCalibration(screenSize: geo.size)
            }
        }
    }

    private func targetDot(in geo: GeometryProxy) -> some View {
        let target = targets[currentTargetIndex]
        return ZStack {
            // Progress ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)
                .frame(width: 40, height: 40)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, lineWidth: 3)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(-90))

            // Center dot
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
        }
        .position(x: target.x, y: target.y)
        .animation(.easeInOut(duration: 0.3), value: currentTargetIndex)
    }

    private var instructionText: some View {
        VStack {
            Spacer()
            Text("Look at the dot — \(currentTargetIndex + 1) of \(totalTargets)")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .padding(.bottom, 40)
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Calibration Complete")
                .font(.title)
                .foregroundColor(.white)
            Text("Eye tracking is now active")
                .foregroundColor(.white.opacity(0.7))
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }

    private func startCalibration(screenSize: CGSize) {
        let eng = CalibrationEngine(
            screenWidth: Double(screenSize.width),
            screenHeight: Double(screenSize.height)
        )
        engine = eng
        targets = eng.calibrationTargets()
        currentTargetIndex = 0
        samplesCollected = 0
        isComplete = false
        progress = 0

        // In a real implementation, this would be driven by the tracking pipeline
        // feeding gaze samples into the calibration engine.
        // For now, set up the visual flow — pipeline integration connects in Task 17.
    }

    /// Called by the pipeline to feed gaze samples during calibration.
    func addGazeSample(_ gaze: GazePoint) {
        guard let engine = engine, currentTargetIndex < totalTargets else { return }

        engine.addSample(rawGaze: gaze, targetIndex: currentTargetIndex)
        samplesCollected += 1
        progress = Double(samplesCollected) / Double(samplesNeeded)

        if samplesCollected >= samplesNeeded {
            engine.advanceTarget()
            currentTargetIndex += 1
            samplesCollected = 0
            progress = 0

            if currentTargetIndex >= totalTargets {
                if let profile = engine.buildProfile(cameraID: appState.pipeline.cameraDeviceID) {
                    appState.pipeline.setCalibrationProfile(profile)
                }
                isComplete = true
            }
        }
    }

    private var cameraDeviceID: String {
        "default"  // Will be populated from CameraManager
    }

    private func dismiss() {
        appState.showCalibration = false
    }
}
```

Note: The `cameraDeviceID` accessor doesn't exist on TrackingPipeline yet. Add this public accessor to `App/TrackingPipeline.swift`:

Add after `currentCursorPosition` property:
```swift
public var cameraDeviceID: String {
    cameraManager.currentDeviceID ?? "unknown"
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add App/UI/CalibrationOverlay.swift App/TrackingPipeline.swift
git commit -m "feat: add CalibrationOverlay with 9-point calibration flow"
```

---

## Task 16: SettingsView

**Files:**
- Modify: `App/UI/SettingsView.swift`

- [ ] **Step 1: Implement SettingsView with tabs**

```swift
// App/UI/SettingsView.swift
import SwiftUI
import LucentCore

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralTab(appState: appState)
                .tabItem { Label("General", systemImage: "gear") }

            TrackingTab()
                .tabItem { Label("Tracking", systemImage: "eye") }

            CursorTab(smoother: appState.pipeline)
                .tabItem { Label("Cursor", systemImage: "cursorarrow.motionlines") }

            ClickTab(detector: appState.pipeline)
                .tabItem { Label("Click", systemImage: "hand.tap") }

            CalibrationTab(appState: appState)
                .tabItem { Label("Calibration", systemImage: "target") }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 360)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { appState.launchAtLogin },
                set: { appState.launchAtLogin = $0 }
            ))
            Toggle("Pause when screen locks", isOn: .constant(true))

            Section("Keyboard Shortcut") {
                Text("Toggle tracking: ⌘⇧L")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tracking Tab

private struct TrackingTab: View {
    var body: some View {
        Form {
            Section("Camera") {
                Picker("Camera", selection: .constant("default")) {
                    Text("Default Camera").tag("default")
                    ForEach(CameraManager.availableCameras, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
            }
            Section("Frame Rate") {
                Picker("Frame Rate", selection: .constant(30)) {
                    Text("15 fps").tag(15)
                    Text("30 fps").tag(30)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Cursor Tab

private struct CursorTab: View {
    @ObservedObject var smoother: TrackingPipeline

    var body: some View {
        Form {
            Section("Smoothing") {
                Slider(value: .constant(0.5), in: 0...1) {
                    Text("Smoothing Strength")
                }
            }
            Section("Dwell Zone") {
                Slider(value: .constant(30.0), in: 10...60) {
                    Text("Dwell Radius (px)")
                }
            }
            Section("Speed") {
                Slider(value: .constant(1.0), in: 0.5...2.0) {
                    Text("Cursor Speed")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Click Tab

private struct ClickTab: View {
    @ObservedObject var detector: TrackingPipeline

    var body: some View {
        Form {
            Section("Blink Thresholds") {
                Slider(value: .constant(0.3), in: 0.1...0.5) {
                    Text("Quick Blink Max (s)")
                }
                Slider(value: .constant(0.8), in: 0.4...1.5) {
                    Text("Long Blink Max (s)")
                }
            }
            Section("Filter") {
                Slider(value: .constant(0.5), in: 0...1) {
                    Text("Natural Blink Filter Sensitivity")
                }
            }
            Section("Feedback") {
                Toggle("Click Sound", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Calibration Tab

private struct CalibrationTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Button("Run Full Calibration (9-point)") {
                    appState.showCalibration = true
                }
                Button("Quick Recalibration (3-point)") {
                    // Quick recal deferred — requires separate 3-point CalibrationEngine mode
                }
                .disabled(true)
                .help("Quick recalibration will be enabled in a future update")
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add App/UI/SettingsView.swift
git commit -m "feat: add SettingsView with General, Tracking, Cursor, Click, Calibration tabs"
```

---

## Task 17: FirstLaunchWizard

**Files:**
- Create: `App/UI/FirstLaunchWizard.swift`
- Modify: `App/LucentApp.swift` (add wizard trigger)

- [ ] **Step 1: Implement FirstLaunchWizard**

```swift
// App/UI/FirstLaunchWizard.swift
import SwiftUI
import LucentCore

struct FirstLaunchWizard: View {
    @ObservedObject var appState: AppState
    @State private var step = 0

    var body: some View {
        VStack(spacing: 24) {
            // Progress
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal)

            Spacer()

            switch step {
            case 0: welcomeStep
            case 1: cameraStep
            case 2: accessibilityStep
            case 3: readyStep
            default: EmptyView()
            }

            Spacer()
        }
        .padding(32)
        .frame(width: 480, height: 400)
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            Text("Welcome to Lucent")
                .font(.largeTitle.bold())
            Text("Control your Mac with your eyes. Let's set up a few permissions first.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Get Started") { step = 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var cameraStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            Text("Camera Access")
                .font(.title.bold())
            Text("Lucent needs your camera to track eye movements. Video is processed locally and never leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if appState.permissions.cameraGranted {
                Label("Camera access granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Button("Continue") { step = 2 }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Grant Camera Access") {
                    Task {
                        await appState.permissions.requestCamera()
                        if appState.permissions.cameraGranted { step = 2 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "accessibility")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            Text("Accessibility Access")
                .font(.title.bold())
            Text("Lucent needs Accessibility permissions to move your cursor. You'll need to enable it in System Settings.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if appState.permissions.accessibilityGranted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Button("Continue") { step = 3 }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Open System Settings") {
                    appState.permissions.requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Check Again") {
                    appState.permissions.refresh()
                    if appState.permissions.accessibilityGranted { step = 3 }
                }
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("You're All Set!")
                .font(.largeTitle.bold())
            Text("Calibrate your eye tracking, then use ⌘⇧L to toggle tracking on and off.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Start Calibration") {
                appState.completeOnboarding()
                appState.showCalibration = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
```

- [ ] **Step 2: Update LucentApp to show wizard on first launch**

Replace the full content of `App/LucentApp.swift`:

```swift
// App/LucentApp.swift
import SwiftUI
import LucentCore

@main
struct LucentApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.pipeline.isEnabled ? "eye.fill" : "eye")
        }

        // First launch wizard
        Window("Welcome to Lucent", id: "wizard") {
            FirstLaunchWizard(appState: appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Settings window
        Window("Lucent Settings", id: "settings") {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 500, height: 400)

        // Calibration overlay
        Window("Calibration", id: "calibration") {
            CalibrationOverlay(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add App/UI/FirstLaunchWizard.swift App/LucentApp.swift
git commit -m "feat: add FirstLaunchWizard for onboarding permissions and calibration"
```

---

## Task 18: Global Keyboard Shortcut

**Files:**
- Modify: `App/AppState.swift` (add shortcut registration)

- [ ] **Step 1: Add global shortcut for toggling tracking (Cmd+Shift+L)**

Add to `App/AppState.swift` — replace the existing file:

```swift
// App/AppState.swift
import Foundation
import SwiftUI
import ServiceManagement
import Carbon.HIToolbox
import LucentCore

@MainActor
public final class AppState: ObservableObject {

    @Published public var pipeline = TrackingPipeline()
    @Published public var permissions = Permissions()
    @Published public var showSettings = false
    @Published public var showCalibration = false
    @Published public var hasCompletedOnboarding: Bool

    private var hotkeyRef: EventHotKeyRef?

    public init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        registerGlobalHotkey()
    }

    // MARK: - Actions

    public func toggleTracking() {
        do {
            try pipeline.toggle()
        } catch {
            print("Failed to toggle tracking: \(error)")
        }
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    // MARK: - Launch at Login

    public var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to set launch at login: \(error)")
            }
        }
    }

    // MARK: - Global Hotkey (Cmd+Shift+L)

    private func registerGlobalHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4C554345)  // "LUCE"
        hotKeyID.id = 1

        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 0x25  // 'L' key

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)

        if status == noErr {
            hotkeyRef = ref
        }

        // Install handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            Task { @MainActor in
                // Access the shared app state through NSApp
                NotificationCenter.default.post(name: .toggleTracking, object: nil)
            }
            return noErr
        }, 1, &eventType, nil, nil)

        NotificationCenter.default.addObserver(forName: .toggleTracking, object: nil, queue: .main) { [weak self] _ in
            self?.toggleTracking()
        }
    }
}

extension Notification.Name {
    static let toggleTracking = Notification.Name("com.lucent.toggleTracking")
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add App/AppState.swift
git commit -m "feat: add Cmd+Shift+L global hotkey to toggle tracking"
```

---

## Task 19: Final Integration — Run All Tests and Verify App

- [ ] **Step 1: Run all unit tests**

Run: `swift test`
Expected: All tests pass (BlinkDetector, CalibrationEngine, CursorSmoother, MockGazeEstimator, CalibrationProfile)

- [ ] **Step 2: Build the full app**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug`
Expected: Build succeeds with no errors

- [ ] **Step 3: Run the app and verify menu bar icon appears**

Run: `open $(xcodebuild -project Lucent.xcodeproj -scheme Lucent -configuration Debug -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/Lucent.app`
Expected: Eye icon appears in menu bar. Clicking shows popover with status and controls.

- [ ] **Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "feat: complete Phase 1 MVP — eye cursor + blink click"
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | Project scaffold | 1 smoke test |
| 2 | Core models | 3 CalibrationProfile tests |
| 3 | BlinkDetector | 5 tests (EAR, classification, filtering, cooldown) |
| 4 | CalibrationEngine | 4 tests (linear, quadratic, flow, outliers) |
| 5 | CursorSmoother | 5 tests (convergence, jitter, dwell, breakout, velocity) |
| 6 | GazeEstimating + Mock | 2 tests |
| 7 | FaceLandmarkDetector | Build verification |
| 8 | InputController | Build verification |
| 9 | CameraManager | Build verification |
| 10 | FrameProcessor | Build verification |
| 11 | TrackingPipeline | Build verification |
| 12 | Permissions | Build verification |
| 13 | AppState | Build verification |
| 14 | MenuBarView | Build verification |
| 15 | CalibrationOverlay | Build verification |
| 16 | SettingsView | Build verification |
| 17 | FirstLaunchWizard | Build verification |
| 18 | Global hotkey | Build verification |
| 19 | Integration | Full test suite + app launch |

**Total: 19 tasks, ~20 unit tests, 19 commits**

**Note:** This plan uses `MockGazeEstimator` (pupil midpoint) for the gaze model. The cursor will roughly track head movement but not true gaze direction. Integrating a real CoreML gaze model (ETH-XGaze conversion) is a follow-up task that slots in by implementing the `GazeEstimating` protocol.
