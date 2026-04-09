# Phase 4: Air Typing / Virtual Keyboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable air typing via a floating virtual QWERTY keyboard controlled by hand tracking (finger tap detection, key resolution), with prefix-based word prediction (bundled 10K word dictionary), prediction selection via eye gaze + blink, all integrated into the existing tracking pipeline and mode system.
**Architecture:** VirtualKeyboard defines the QWERTY layout as pure data. TapDetector watches index fingertip Y-position for downward tap motions. KeyResolver maps fingertip screen coordinates to the nearest key with fuzzy matching. PredictionEngine loads a bundled frequency dictionary and returns top-3 prefix completions. TypingSession manages the text buffer and posts keystrokes via InputController.pressKey(). KeyboardOverlay and PredictionBar are floating NSPanel UIs. TrackingPipeline orchestrates all components in keyboard mode, remapping gestures (swipe-left to backspace, fist to enter, thumb-tap to space). InputModeManager gains a .keyboard mode activated by Cmd+Shift+K.
**Tech Stack:** Apple Vision (hand landmarks via Phase 3 HandDetector), CoreGraphics event system, AppKit NSPanel, SwiftUI, Swift Testing framework
---

### Task 1: Models -- VirtualKeyboard, KeyLayout, InputMode.keyboard
**Files:**
- Create: `Sources/LucentCore/Models/VirtualKeyboard.swift`
- Modify: `Sources/LucentCore/Models/InputMode.swift`

- [ ] **Step 1: Add `.keyboard` case to InputMode and add KeyboardActionType**

Modify `Sources/LucentCore/Models/InputMode.swift` to add the keyboard input mode and keyboard-specific event types.

```swift
import Foundation

public enum InputMode: String, Codable, Sendable, CaseIterable {
    case normal
    case scroll
    case dictation
    case commandPalette
    case keyboard
}

public enum ExpressionType: String, Codable, Sendable, CaseIterable {
    case winkLeft
    case winkRight
    case smile
    case browRaise
    case mouthOpen
}

public struct DetectedExpression: Sendable, Equatable {
    public let type: ExpressionType
    public let confidence: Double
    public let timestamp: Double

    public init(type: ExpressionType, confidence: Double, timestamp: Double) {
        self.type = type
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

public struct ExpressionConfig: Codable, Sendable {
    public var holdDuration: Double
    public var cooldown: Double
    public var thresholdMultiplier: Double

    public init(holdDuration: Double, cooldown: Double, thresholdMultiplier: Double) {
        self.holdDuration = holdDuration
        self.cooldown = cooldown
        self.thresholdMultiplier = thresholdMultiplier
    }

    public static let defaults: [ExpressionType: ExpressionConfig] = [
        .winkLeft: ExpressionConfig(holdDuration: 0.15, cooldown: 0.3, thresholdMultiplier: 1.0),
        .winkRight: ExpressionConfig(holdDuration: 0.15, cooldown: 0.3, thresholdMultiplier: 1.0),
        .smile: ExpressionConfig(holdDuration: 0.5, cooldown: 0.5, thresholdMultiplier: 1.4),
        .browRaise: ExpressionConfig(holdDuration: 0.3, cooldown: 0.5, thresholdMultiplier: 1.3),
        .mouthOpen: ExpressionConfig(holdDuration: 0.3, cooldown: 0.5, thresholdMultiplier: 2.0),
    ]
}

public enum ModeEvent: Equatable, Sendable {
    case modeChanged(from: InputMode, to: InputMode)
    case actionTriggered(ExpressionType)
    case keyboardAction(KeyboardActionType)
}

public enum KeyboardActionType: Equatable, Sendable {
    case keyTapped(character: String, keyCode: UInt16)
    case wordCompleted(word: String)
    case backspace
    case space
    case enter
}
```

```bash
swift build 2>&1 | head -30
```

- [ ] **Step 2: Create VirtualKeyboard.swift with QWERTY layout data**

Create `Sources/LucentCore/Models/VirtualKeyboard.swift`:

```swift
import Foundation
import CoreGraphics

// MARK: - Key Definition

public struct KeyDefinition: Sendable, Equatable, Hashable {
    public let label: String
    public let keyCode: UInt16
    public let position: CGPoint   // Normalized in keyboard space (0..1, 0..1)
    public let size: CGSize        // Normalized in keyboard space
    public let row: Int

    public init(label: String, keyCode: UInt16, position: CGPoint, size: CGSize, row: Int) {
        self.label = label
        self.keyCode = keyCode
        self.position = position
        self.size = size
        self.row = row
    }

    /// Center point of the key in keyboard-local normalized coordinates.
    public var center: CGPoint {
        CGPoint(x: position.x + size.width / 2.0, y: position.y + size.height / 2.0)
    }
}

// MARK: - Virtual Keyboard

public struct VirtualKeyboard: Sendable {
    public let keys: [KeyDefinition]
    public let rows: Int
    public let columns: Int

    public init(keys: [KeyDefinition], rows: Int, columns: Int) {
        self.keys = keys
        self.rows = rows
        self.columns = columns
    }

    /// Standard QWERTY layout with 4 rows (3 letter rows + space bar).
    public static let qwerty: VirtualKeyboard = {
        var keys: [KeyDefinition] = []

        let keyWidth: CGFloat = 0.1
        let keyHeight: CGFloat = 0.25
        let keySize = CGSize(width: keyWidth, height: keyHeight)

        // Row 0: Q W E R T Y U I O P (10 keys, no stagger)
        let row0Letters: [(String, UInt16)] = [
            ("Q", 0x0C), ("W", 0x0D), ("E", 0x0E), ("R", 0x0F), ("T", 0x11),
            ("Y", 0x10), ("U", 0x20), ("I", 0x22), ("O", 0x1F), ("P", 0x23),
        ]
        let row0Stagger: CGFloat = 0.0
        for (i, (label, code)) in row0Letters.enumerated() {
            let x = row0Stagger + CGFloat(i) * keyWidth
            let y: CGFloat = 0.0
            keys.append(KeyDefinition(label: label, keyCode: code, position: CGPoint(x: x, y: y), size: keySize, row: 0))
        }

        // Row 1: A S D F G H J K L (9 keys, 0.05 stagger)
        let row1Letters: [(String, UInt16)] = [
            ("A", 0x00), ("S", 0x01), ("D", 0x02), ("F", 0x03), ("G", 0x05),
            ("H", 0x04), ("J", 0x26), ("K", 0x28), ("L", 0x25),
        ]
        let row1Stagger: CGFloat = 0.05
        for (i, (label, code)) in row1Letters.enumerated() {
            let x = row1Stagger + CGFloat(i) * keyWidth
            let y: CGFloat = keyHeight
            keys.append(KeyDefinition(label: label, keyCode: code, position: CGPoint(x: x, y: y), size: keySize, row: 1))
        }

        // Row 2: Z X C V B N M (7 keys, 0.15 stagger)
        let row2Letters: [(String, UInt16)] = [
            ("Z", 0x06), ("X", 0x07), ("C", 0x08), ("V", 0x09), ("B", 0x0B),
            ("N", 0x2D), ("M", 0x2E),
        ]
        let row2Stagger: CGFloat = 0.15
        for (i, (label, code)) in row2Letters.enumerated() {
            let x = row2Stagger + CGFloat(i) * keyWidth
            let y: CGFloat = keyHeight * 2
            keys.append(KeyDefinition(label: label, keyCode: code, position: CGPoint(x: x, y: y), size: keySize, row: 2))
        }

        // Row 3: Space bar (60% width, centered)
        let spaceWidth: CGFloat = 0.6
        let spaceX: CGFloat = 0.2  // Centered: (1.0 - 0.6) / 2
        keys.append(KeyDefinition(
            label: "space",
            keyCode: 0x31,
            position: CGPoint(x: spaceX, y: keyHeight * 3),
            size: CGSize(width: spaceWidth, height: keyHeight),
            row: 3
        ))

        return VirtualKeyboard(keys: keys, rows: 4, columns: 10)
    }()

    /// Look up a KeyDefinition by its label (case-insensitive).
    public func key(labeled label: String) -> KeyDefinition? {
        keys.first { $0.label.lowercased() == label.lowercased() }
    }

    /// Look up a KeyDefinition by its keyCode.
    public func key(forKeyCode keyCode: UInt16) -> KeyDefinition? {
        keys.first { $0.keyCode == keyCode }
    }

    /// Map a character (e.g. "a") to its macOS virtual keyCode.
    public static func keyCode(for character: Character) -> UInt16? {
        let charMap: [Character: UInt16] = [
            "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
            "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
            "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
            "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
            "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
            "z": 0x06, " ": 0x31,
        ]
        return charMap[character]
    }
}
```

```bash
swift build 2>&1 | head -30
```

- [ ] **Step 3: Create VirtualKeyboardTests.swift to verify layout**

Write `Tests/LucentCoreTests/VirtualKeyboardTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import LucentCore

@Test func qwertyHas27Keys() {
    let kb = VirtualKeyboard.qwerty
    // 10 + 9 + 7 + 1 (space) = 27
    #expect(kb.keys.count == 27)
}

@Test func qwertyHas4Rows() {
    let kb = VirtualKeyboard.qwerty
    #expect(kb.rows == 4)
    let rowCounts = Dictionary(grouping: kb.keys, by: \.row).mapValues(\.count)
    #expect(rowCounts[0] == 10)
    #expect(rowCounts[1] == 9)
    #expect(rowCounts[2] == 7)
    #expect(rowCounts[3] == 1)
}

@Test func noKeysOverlap() {
    let kb = VirtualKeyboard.qwerty
    for i in 0..<kb.keys.count {
        for j in (i + 1)..<kb.keys.count {
            let a = kb.keys[i]
            let b = kb.keys[j]
            let aRight = a.position.x + a.size.width
            let aBottom = a.position.y + a.size.height
            let bRight = b.position.x + b.size.width
            let bBottom = b.position.y + b.size.height
            let overlapsX = a.position.x < bRight && aRight > b.position.x
            let overlapsY = a.position.y < bBottom && aBottom > b.position.y
            if overlapsX && overlapsY {
                Issue.record("Keys \(a.label) and \(b.label) overlap")
            }
        }
    }
}

@Test func allKeyCodesAreUnique() {
    let kb = VirtualKeyboard.qwerty
    let codes = kb.keys.map(\.keyCode)
    let unique = Set(codes)
    #expect(codes.count == unique.count, "Duplicate key codes found")
}

@Test func keyLookupByLabel() {
    let kb = VirtualKeyboard.qwerty
    let q = kb.key(labeled: "Q")
    #expect(q != nil)
    #expect(q?.keyCode == 0x0C)

    let space = kb.key(labeled: "space")
    #expect(space != nil)
    #expect(space?.keyCode == 0x31)
}

@Test func keyCodeMapping() {
    #expect(VirtualKeyboard.keyCode(for: "a") == 0x00)
    #expect(VirtualKeyboard.keyCode(for: "z") == 0x06)
    #expect(VirtualKeyboard.keyCode(for: " ") == 0x31)
    #expect(VirtualKeyboard.keyCode(for: "1") == nil)
}

@Test func keyCentersAreWithinBounds() {
    let kb = VirtualKeyboard.qwerty
    for key in kb.keys {
        let center = key.center
        #expect(center.x >= 0 && center.x <= 1.0, "Key \(key.label) center X out of bounds: \(center.x)")
        #expect(center.y >= 0 && center.y <= 1.0, "Key \(key.label) center Y out of bounds: \(center.y)")
    }
}

@Test func row0StartsAtOrigin() {
    let kb = VirtualKeyboard.qwerty
    let firstKey = kb.keys.first { $0.row == 0 && $0.label == "Q" }
    #expect(firstKey != nil)
    #expect(firstKey!.position.x == 0.0)
    #expect(firstKey!.position.y == 0.0)
}
```

```bash
swift test 2>&1 | tail -20
```

---

### Task 2: TapDetector (TDD)
**Files:**
- Create: `Tests/LucentCoreTests/TapDetectorTests.swift`
- Create: `Sources/LucentCore/Tracking/TapDetector.swift`

- [ ] **Step 1: Write TapDetector tests first (red phase)**

Write `Tests/LucentCoreTests/TapDetectorTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import LucentCore

// MARK: - Test Helpers

/// Create a minimal HandData with a specified index fingertip Y position.
private func makeHandData(indexTipY: CGFloat, timestamp: Double, confidence: Float = 0.9) -> HandData {
    var landmarks: [HandJoint: CGPoint] = [:]
    // Minimal landmarks: wrist and index tip
    landmarks[.wrist] = CGPoint(x: 0.5, y: 0.8)
    landmarks[.indexTip] = CGPoint(x: 0.5, y: indexTipY)
    landmarks[.indexMCP] = CGPoint(x: 0.5, y: 0.7)
    landmarks[.indexPIP] = CGPoint(x: 0.5, y: 0.65)
    landmarks[.indexDIP] = CGPoint(x: 0.5, y: 0.6)
    // Thumb and other fingers at rest
    landmarks[.thumbTip] = CGPoint(x: 0.4, y: 0.7)
    landmarks[.thumbCMC] = CGPoint(x: 0.45, y: 0.75)
    landmarks[.thumbMP] = CGPoint(x: 0.42, y: 0.72)
    landmarks[.thumbIP] = CGPoint(x: 0.41, y: 0.71)
    landmarks[.middleTip] = CGPoint(x: 0.55, y: 0.55)
    landmarks[.middleMCP] = CGPoint(x: 0.55, y: 0.7)
    landmarks[.middlePIP] = CGPoint(x: 0.55, y: 0.65)
    landmarks[.middleDIP] = CGPoint(x: 0.55, y: 0.6)
    landmarks[.ringTip] = CGPoint(x: 0.6, y: 0.58)
    landmarks[.ringMCP] = CGPoint(x: 0.6, y: 0.7)
    landmarks[.ringPIP] = CGPoint(x: 0.6, y: 0.65)
    landmarks[.ringDIP] = CGPoint(x: 0.6, y: 0.6)
    landmarks[.littleTip] = CGPoint(x: 0.65, y: 0.6)
    landmarks[.littleMCP] = CGPoint(x: 0.65, y: 0.7)
    landmarks[.littlePIP] = CGPoint(x: 0.65, y: 0.65)
    landmarks[.littleDIP] = CGPoint(x: 0.65, y: 0.62)

    let fingerStates: [Finger: FingerState] = [
        .thumb: .extended, .index: .extended, .middle: .extended,
        .ring: .extended, .little: .extended,
    ]
    return HandData(
        landmarks: landmarks,
        fingerStates: fingerStates,
        wristPosition: CGPoint(x: 0.5, y: 0.8),
        chirality: .right,
        confidence: confidence,
        timestamp: timestamp
    )
}

// MARK: - Tests

@Test func noTapDuringBaselineCollection() {
    let detector = TapDetector()
    // Feed a few frames at baseline Y -- should not fire
    for i in 0..<5 {
        let result = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
        #expect(result == nil, "Should not fire tap during baseline collection (frame \(i))")
    }
}

@Test func detectsSimpleTapDownAndUp() {
    let config = TapConfig(
        tapThreshold: 0.04,
        returnThreshold: 0.02,
        maxTapDuration: 0.4,
        tapCooldown: 0.15,
        baselineWindowSize: 5,
        minimumConfidence: 0.5
    )
    let detector = TapDetector(config: config)

    // Build baseline at Y=0.55 (5 frames)
    for i in 0..<5 {
        let _ = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
    }

    // Tap down: Y drops to 0.60 (0.05 below baseline of ~0.55, exceeds threshold of 0.04)
    let tapDown = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.20))
    #expect(tapDown == nil, "Tap-down alone should not fire event")

    // Tap up: Y returns to 0.55 (within returnThreshold of baseline)
    let tapUp = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.25))
    #expect(tapUp != nil, "Tap-up should fire tap event")
}

@Test func tapCooldownPreventsDoubleFire() {
    let config = TapConfig(
        tapThreshold: 0.04,
        returnThreshold: 0.02,
        maxTapDuration: 0.4,
        tapCooldown: 0.15,
        baselineWindowSize: 5,
        minimumConfidence: 0.5
    )
    let detector = TapDetector(config: config)

    // Build baseline
    for i in 0..<5 {
        let _ = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
    }

    // First tap
    let _ = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.20))
    let first = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.25))
    #expect(first != nil)

    // Immediate second tap (within cooldown of 0.15s)
    let _ = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.28))
    let second = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.33))
    #expect(second == nil, "Second tap within cooldown should not fire")

    // Third tap after cooldown expires (0.25 + 0.15 = 0.40)
    let _ = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.45))
    let third = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.50))
    #expect(third != nil, "Tap after cooldown should fire")
}

@Test func rejectsLowConfidenceHandData() {
    let detector = TapDetector()
    // Feed frames with confidence below minimum
    for i in 0..<10 {
        let result = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033, confidence: 0.2))
        #expect(result == nil)
    }
}

@Test func tapTooSlowIsRejected() {
    let config = TapConfig(
        tapThreshold: 0.04,
        returnThreshold: 0.02,
        maxTapDuration: 0.2,  // Very short window
        tapCooldown: 0.15,
        baselineWindowSize: 5,
        minimumConfidence: 0.5
    )
    let detector = TapDetector(config: config)

    // Build baseline
    for i in 0..<5 {
        let _ = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
    }

    // Tap down
    let _ = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.20))
    // Tap up too late (0.20 + 0.30 = 0.50, exceeds maxTapDuration of 0.2)
    let result = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.50))
    #expect(result == nil, "Tap exceeding maxTapDuration should not fire")
}

@Test func resetClearsState() {
    let detector = TapDetector()
    // Build some baseline
    for i in 0..<10 {
        let _ = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
    }
    detector.reset()
    // After reset, first frames should rebuild baseline (no tap)
    let result = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 1.0))
    #expect(result == nil, "Should not fire tap right after reset")
}

@Test func tapEventContainsFingertipPosition() {
    let config = TapConfig(
        tapThreshold: 0.04,
        returnThreshold: 0.02,
        maxTapDuration: 0.4,
        tapCooldown: 0.15,
        baselineWindowSize: 5,
        minimumConfidence: 0.5
    )
    let detector = TapDetector(config: config)

    // Build baseline
    for i in 0..<5 {
        let _ = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: Double(i) * 0.033))
    }

    // Tap
    let _ = detector.update(handData: makeHandData(indexTipY: 0.60, timestamp: 0.20))
    let event = detector.update(handData: makeHandData(indexTipY: 0.55, timestamp: 0.25))
    #expect(event != nil)
    #expect(event!.fingertipPosition.x == 0.5, "Fingertip X should match hand data")
}
```

```bash
swift test 2>&1 | tail -20
```

- [ ] **Step 2: Implement TapDetector (green phase)**

Create `Sources/LucentCore/Tracking/TapDetector.swift`:

```swift
import Foundation
import CoreGraphics

// MARK: - Configuration

public struct TapConfig: Sendable {
    public var tapThreshold: Double
    public var returnThreshold: Double
    public var maxTapDuration: Double
    public var tapCooldown: Double
    public var baselineWindowSize: Int
    public var minimumConfidence: Float

    public init(
        tapThreshold: Double = 0.04,
        returnThreshold: Double = 0.02,
        maxTapDuration: Double = 0.4,
        tapCooldown: Double = 0.15,
        baselineWindowSize: Int = 10,
        minimumConfidence: Float = 0.5
    ) {
        self.tapThreshold = tapThreshold
        self.returnThreshold = returnThreshold
        self.maxTapDuration = maxTapDuration
        self.tapCooldown = tapCooldown
        self.baselineWindowSize = baselineWindowSize
        self.minimumConfidence = minimumConfidence
    }

    public static let defaults = TapConfig()
}

// MARK: - Tap Event

public struct TapEvent: Sendable, Equatable {
    public let fingertipPosition: CGPoint
    public let timestamp: Double

    public init(fingertipPosition: CGPoint, timestamp: Double) {
        self.fingertipPosition = fingertipPosition
        self.timestamp = timestamp
    }
}

// MARK: - TapDetector

public final class TapDetector: @unchecked Sendable {

    public var config: TapConfig

    private enum TapPhase {
        case idle
        case down(startTime: Double, startY: Double)
    }

    private var phase: TapPhase = .idle
    private var baselineYValues: [Double] = []
    private var lastTapTimestamp: Double = -1.0
    private var lastHandTimestamp: Double = -1.0

    public init(config: TapConfig = .defaults) {
        self.config = config
    }

    public func reset() {
        phase = .idle
        baselineYValues = []
        lastTapTimestamp = -1.0
        lastHandTimestamp = -1.0
    }

    /// Process a hand data frame. Returns a TapEvent if a complete tap is detected.
    public func update(handData: HandData) -> TapEvent? {
        // Reject low confidence
        guard handData.confidence >= config.minimumConfidence else { return nil }

        // Check for hand loss (>500ms gap) -- reset baseline
        if lastHandTimestamp >= 0 && (handData.timestamp - lastHandTimestamp) > 0.5 {
            reset()
        }
        lastHandTimestamp = handData.timestamp

        // Get index fingertip Y
        guard let indexTip = handData.landmarks[.indexTip] else { return nil }
        let tipY = Double(indexTip.y)

        // Compute baseline
        let baseline = computeBaseline()

        switch phase {
        case .idle:
            // Collect baseline samples when idle
            if baselineYValues.count < config.baselineWindowSize {
                baselineYValues.append(tipY)
                return nil
            }

            // Update rolling baseline
            updateBaseline(tipY)

            // Check cooldown
            if lastTapTimestamp >= 0 && (handData.timestamp - lastTapTimestamp) < config.tapCooldown {
                return nil
            }

            // Check for tap-down: fingertip drops below baseline by threshold
            // In screen coordinates (top-left origin), downward motion = increasing Y
            if let bl = baseline, (tipY - bl) > config.tapThreshold {
                phase = .down(startTime: handData.timestamp, startY: tipY)
            }

            return nil

        case .down(let startTime, _):
            guard let bl = baseline else {
                phase = .idle
                return nil
            }

            // Check if tap took too long
            if (handData.timestamp - startTime) > config.maxTapDuration {
                phase = .idle
                updateBaseline(tipY)
                return nil
            }

            // Check for tap-up: fingertip returns near baseline
            if abs(tipY - bl) <= config.returnThreshold {
                phase = .idle
                lastTapTimestamp = handData.timestamp
                updateBaseline(tipY)
                return TapEvent(
                    fingertipPosition: indexTip,
                    timestamp: handData.timestamp
                )
            }

            return nil
        }
    }

    // MARK: - Private

    private func computeBaseline() -> Double? {
        guard baselineYValues.count >= config.baselineWindowSize else { return nil }
        return baselineYValues.suffix(config.baselineWindowSize).reduce(0.0, +) / Double(config.baselineWindowSize)
    }

    private func updateBaseline(_ y: Double) {
        baselineYValues.append(y)
        // Keep only the last N*2 values to prevent unbounded growth
        let maxSize = config.baselineWindowSize * 2
        if baselineYValues.count > maxSize {
            baselineYValues = Array(baselineYValues.suffix(maxSize))
        }
    }
}
```

```bash
swift test 2>&1 | tail -20
```

---

### Task 3: KeyResolver (TDD)
**Files:**
- Create: `Tests/LucentCoreTests/KeyResolverTests.swift`
- Create: `Sources/LucentCore/Tracking/KeyResolver.swift`

- [ ] **Step 1: Write KeyResolver tests first (red phase)**

Write `Tests/LucentCoreTests/KeyResolverTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import LucentCore

// MARK: - Test Helpers

private let testKeyboardFrame = CGRect(x: 100, y: 600, width: 600, height: 200)

// MARK: - Tests

@Test func resolvesExactKeyCenter() {
    let resolver = KeyResolver()
    let kb = VirtualKeyboard.qwerty
    // Key "Q" is at position (0.0, 0.0) with size (0.1, 0.25)
    // Center in keyboard space: (0.05, 0.125)
    // Screen position: (100 + 0.05*600, 600 + 0.125*200) = (130, 625)
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 130, y: 625),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result != nil)
    #expect(result?.label == "Q")
}

@Test func resolvesNearbyPosition() {
    let resolver = KeyResolver()
    // Slightly off from Q center but within hit radius
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 135, y: 630),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result != nil)
    #expect(result?.label == "Q")
}

@Test func returnsNilForOutOfBoundsPosition() {
    let resolver = KeyResolver()
    // Way outside the keyboard
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 50, y: 300),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result == nil)
}

@Test func resolvesSpaceBar() {
    let resolver = KeyResolver()
    // Space bar center: position (0.2, 0.75), size (0.6, 0.25)
    // Center in keyboard space: (0.5, 0.875)
    // Screen: (100 + 0.5*600, 600 + 0.875*200) = (400, 775)
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 400, y: 775),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result != nil)
    #expect(result?.label == "space")
}

@Test func resolvesRow1WithStagger() {
    let resolver = KeyResolver()
    // Key "A" is at position (0.05, 0.25) with size (0.1, 0.25)
    // Center: (0.10, 0.375)
    // Screen: (100 + 0.10*600, 600 + 0.375*200) = (160, 675)
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 160, y: 675),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result != nil)
    #expect(result?.label == "A")
}

@Test func resolvesRow2WithStagger() {
    let resolver = KeyResolver()
    // Key "Z" is at position (0.15, 0.5) with size (0.1, 0.25)
    // Center: (0.20, 0.625)
    // Screen: (100 + 0.20*600, 600 + 0.625*200) = (220, 725)
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 220, y: 725),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result != nil)
    #expect(result?.label == "Z")
}

@Test func nearestKeyReturnsClosestWithDistance() {
    let resolver = KeyResolver()
    let result = resolver.nearestKey(localPosition: CGPoint(x: 0.05, y: 0.125))
    #expect(result != nil)
    #expect(result?.key.label == "Q")
    #expect(result!.distance < 0.01)
}

@Test func fuzzyMarginAllowsSlightlyOutsideKeyboard() {
    let config = KeyResolverConfig(fuzzyMargin: 0.05, maxHitRadius: 0.08)
    let resolver = KeyResolver(config: config)
    // Position slightly to the left of keyboard bounds
    // Screen X = 100 - 10 = 90 -> localX = -10/600 = -0.017 (within fuzzyMargin of 0.05)
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 90, y: 625),
        keyboardFrame: testKeyboardFrame
    )
    // Should still match Q since it's within fuzzy margin and hit radius
    #expect(result != nil)
    #expect(result?.label == "Q")
}

@Test func tooFarFromAnyKeyReturnsNil() {
    let config = KeyResolverConfig(fuzzyMargin: 0.05, maxHitRadius: 0.02)  // Very tight radius
    let resolver = KeyResolver(config: config)
    // Position between Q and W but with tight radius should still match one
    // Midpoint between Q center (0.05, 0.125) and W center (0.15, 0.125): (0.10, 0.125)
    // Distance to Q = 0.05, distance to W = 0.05 -- both exceed maxHitRadius of 0.02
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 160, y: 625),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result == nil)
}
```

```bash
swift test 2>&1 | tail -20
```

- [ ] **Step 2: Implement KeyResolver (green phase)**

Create `Sources/LucentCore/Tracking/KeyResolver.swift`:

```swift
import Foundation
import CoreGraphics

// MARK: - Configuration

public struct KeyResolverConfig: Sendable {
    public var fuzzyMargin: Double
    public var maxHitRadius: Double

    public init(
        fuzzyMargin: Double = 0.05,
        maxHitRadius: Double = 0.08
    ) {
        self.fuzzyMargin = fuzzyMargin
        self.maxHitRadius = maxHitRadius
    }

    public static let defaults = KeyResolverConfig()
}

// MARK: - KeyResolver

public final class KeyResolver: Sendable {

    public let keyboard: VirtualKeyboard
    public let config: KeyResolverConfig

    public init(keyboard: VirtualKeyboard = .qwerty, config: KeyResolverConfig = .defaults) {
        self.keyboard = keyboard
        self.config = config
    }

    /// Map a screen-space fingertip position to the nearest key on the virtual keyboard.
    /// Returns nil if the position is outside keyboard bounds (with fuzzy margin)
    /// or if the nearest key is farther than maxHitRadius.
    public func resolve(
        fingertipScreenPosition: CGPoint,
        keyboardFrame: CGRect
    ) -> KeyDefinition? {
        // Convert screen position to keyboard-local normalized coordinates
        let localX = (fingertipScreenPosition.x - keyboardFrame.origin.x) / keyboardFrame.width
        let localY = (fingertipScreenPosition.y - keyboardFrame.origin.y) / keyboardFrame.height

        // Bounds check with fuzzy margin
        guard localX >= -config.fuzzyMargin,
              localX <= 1.0 + config.fuzzyMargin,
              localY >= -config.fuzzyMargin,
              localY <= 1.0 + config.fuzzyMargin else {
            return nil
        }

        let localPoint = CGPoint(x: localX, y: localY)

        guard let (key, distance) = nearestKey(localPosition: localPoint) else {
            return nil
        }

        guard distance <= config.maxHitRadius else {
            return nil
        }

        return key
    }

    /// Find the nearest key to a keyboard-local normalized position.
    /// Returns the key and the Euclidean distance to its center.
    public func nearestKey(localPosition: CGPoint) -> (key: KeyDefinition, distance: Double)? {
        guard !keyboard.keys.isEmpty else { return nil }

        var bestKey: KeyDefinition?
        var bestDistance: Double = .greatestFiniteMagnitude

        for key in keyboard.keys {
            let center = key.center
            let dx = Double(localPosition.x - center.x)
            let dy = Double(localPosition.y - center.y)
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDistance {
                bestDistance = dist
                bestKey = key
            }
        }

        guard let key = bestKey else { return nil }
        return (key, bestDistance)
    }
}
```

```bash
swift test 2>&1 | tail -20
```

---

### Task 4: PredictionEngine (TDD) + Dictionary Resource
**Files:**
- Create: `Sources/LucentCore/Resources/words.txt`
- Create: `Tests/LucentCoreTests/PredictionEngineTests.swift`
- Create: `Sources/LucentCore/Control/PredictionEngine.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Update Package.swift to declare resources**

Modify `Package.swift` to add resource processing for the LucentCore target:

```swift
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
            path: "Sources/LucentCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LucentCoreTests",
            dependencies: ["LucentCore"],
            path: "Tests/LucentCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Create the words.txt dictionary file (500-word subset)**

Create `Sources/LucentCore/Resources/words.txt`:

```
the	23135851162
of	13151942776
and	12997637966
to	12136980858
a	9081174698
in	8469404971
for	5933321709
is	4705743816
on	3750423199
that	3400031103
by	3350048871
this	3228469086
with	3183110675
i	3086225277
you	2996181025
it	2813163874
not	2633487141
or	2590739907
be	2398724162
are	2393335404
from	2275220347
at	2205610798
as	2117860394
all	1912787249
have	1903199608
new	1811325197
more	1718923498
an	1686700779
was	1625764511
we	1582805997
will	1513585502
can	1379182543
us	1340672094
about	1333462498
if	1293277182
my	1252383330
has	1202026447
but	1200675063
one	1188574912
our	1173130229
do	1163082506
no	1152978273
time	1104180662
they	1097752548
he	1095234507
up	1093591077
its	1082527633
only	1068588379
which	1039696565
when	1036472547
make	1021048253
like	1016984941
get	982681279
just	926953654
out	923714485
been	894893385
would	884975733
how	876610553
also	843695757
her	843544675
other	840803690
what	840458815
so	834574821
some	805459157
very	788815455
than	786810872
any	780167957
she	778380349
into	743723587
most	728752654
may	722987972
after	717076136
know	715547640
back	713012095
should	704516573
their	702237765
year	687570025
much	668765783
see	654249991
over	640456217
two	637553997
way	633891011
come	621597769
could	620519737
people	612186216
first	610960953
day	603068693
between	591055927
even	577556571
because	574131155
many	572780271
well	570793115
state	566913419
those	560518781
own	559757050
work	545447408
through	543028575
life	542070360
where	536375951
world	530048828
long	527773233
being	521949561
then	519724823
did	519478218
take	517783149
good	510755946
think	508459697
help	507820972
right	504285523
still	499773905
too	498610585
here	494693399
need	491671937
before	490851614
home	489825835
who	488781113
last	484975596
great	483504085
man	480854458
him	479254750
while	477327263
old	464917277
hand	461093670
high	460629556
part	460120019
off	459782174
go	457939476
same	456556614
each	455498367
look	450539543
down	445488564
use	444084510
find	443655804
small	441654497
place	437285805
end	435849987
now	433645629
head	432155614
point	431741701
little	431015419
give	426590399
must	424810693
big	423654126
never	420543710
house	417312457
school	416210973
say	415963527
might	413289267
since	411898854
under	408539176
thing	406781327
turn	405892103
again	405112547
every	403298714
keep	400915687
system	398921754
start	397256841
show	394652310
city	392841756
number	391542673
play	387465298
move	385412563
group	383125479
water	380987654
run	378654321
change	376543210
set	374987654
try	372543218
ask	370654321
late	368987654
three	366543210
mean	364987654
call	362543218
line	360654321
open	358987654
name	356543210
read	354987654
side	352543218
left	350654321
real	348987654
night	346543210
put	344987654
close	342543218
next	340654321
hard	338987654
live	336543210
both	334987654
story	332543218
few	330654321
write	328987654
along	326543210
light	324987654
always	322543218
tell	320654321
might	318987654
stand	316543210
grow	314987654
body	312543218
face	310654321
watch	308987654
power	306543210
stop	304987654
fact	302543218
second	300654321
sure	298987654
hold	296543210
land	294987654
eye	292543218
young	290654321
love	288987654
black	286543210
child	284987654
white	282543218
begin	280654321
yet	278987654
food	276543210
case	274987654
woman	272543218
talk	270654321
door	268987654
best	266543210
idea	264987654
money	262543218
class	260654321
room	258987654
different	256543210
able	254987654
above	252543218
kind	250654321
large	248987654
often	246543210
early	244987654
year	242543218
family	240654321
enough	238987654
problem	236543210
order	234987654
until	232543218
field	230654321
general	228987654
across	226543210
level	224987654
table	222543218
voice	220654321
less	218987654
better	216543210
plan	214987654
free	212543218
sure	210654321
done	208987654
care	206543210
clear	204987654
human	202543218
leave	200654321
law	198987654
air	196543210
drive	194987654
true	192543218
full	190654321
bit	188987654
bring	186543210
pay	184987654
death	182543218
during	180654321
past	178987654
half	176543210
short	174987654
study	172543218
five	170654321
step	168987654
early	166543210
west	164987654
run	162543218
east	160654321
near	158987654
low	156543210
form	154987654
inside	152543218
rest	150654321
river	148987654
area	146543210
cut	144987654
reach	142543218
draw	140654321
war	138987654
build	136543210
fire	134987654
cover	132543218
feel	130654321
car	128987654
hour	126543210
act	124987654
game	122543218
picture	120654321
lead	118987654
add	116543210
question	114987654
try	112543218
front	110654321
base	108987654
easy	106543210
rule	104987654
almost	102543218
age	100654321
mark	98987654
miss	96543210
nothing	94987654
check	92543218
against	90654321
round	88987654
mother	86543210
behind	84987654
south	82543218
north	80654321
reason	78987654
wish	76543210
head	74987654
simple	72543218
strong	70654321
happen	68987654
ever	66543210
answer	64987654
learn	62543218
interest	60654321
country	58987654
create	56543210
service	54987654
market	52543218
center	50654321
test	48987654
heart	46543210
paper	44987654
result	42543218
record	40654321
produce	38987654
red	36543210
green	34987654
less	32543218
develop	30654321
report	28987654
member	26543210
month	24987654
letter	22543218
week	20654321
matter	18987654
follow	16543210
program	14987654
office	12543218
present	10654321
tree	9987654
spring	9543210
contain	9087654
support	8543218
figure	8054321
minute	7987654
street	7543210
ball	7087654
dark	6543218
product	6054321
river	5987654
force	5543210
fish	5087654
remain	4543218
sit	4054321
brother	3987654
street	3543210
land	3087654
deep	2543218
note	2054321
season	1987654
pull	1543210
price	1087654
enter	543218
major	454321
fill	387654
post	343210
wide	287654
cause	243218
today	220000
pass	210000
sell	200000
song	190000
cold	180000
sense	170000
stay	160000
fall	150000
win	140000
offer	130000
plant	120000
charge	110000
cost	100000
unit	90000
figure	80000
require	70000
press	60000
model	50000
wait	40000
touch	30000
rise	20000
piece	10000
```

- [ ] **Step 3: Write PredictionEngine tests (red phase)**

Write `Tests/LucentCoreTests/PredictionEngineTests.swift`:

```swift
import Testing
@testable import LucentCore

// MARK: - Tests using explicit word list (for deterministic testing)

private let testWords: [(word: String, frequency: Int)] = [
    ("the", 1000),
    ("they", 800),
    ("them", 700),
    ("then", 600),
    ("there", 500),
    ("these", 400),
    ("think", 300),
    ("this", 200),
    ("three", 100),
    ("apple", 900),
    ("application", 850),
    ("apply", 800),
    ("app", 750),
    ("hello", 500),
    ("help", 450),
    ("world", 300),
]

@Test func predictReturnsTopByFrequency() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "th")
    #expect(results.count == 3)
    #expect(results[0] == "the")
    #expect(results[1] == "they")
    #expect(results[2] == "them")
}

@Test func predictIsCaseInsensitive() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "TH")
    #expect(results.count == 3)
    #expect(results[0] == "the")
}

@Test func predictReturnsEmptyForEmptyPrefix() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "")
    #expect(results.isEmpty)
}

@Test func predictReturnsEmptyForNoMatch() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "xyz")
    #expect(results.isEmpty)
}

@Test func predictRespectsMaxResults() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "th", maxResults: 2)
    #expect(results.count == 2)
}

@Test func predictWithExactMatch() {
    let engine = PredictionEngine(words: testWords)
    // "the" is an exact match and also a prefix of "they", "them", "then", "there", "these", "three"
    let results = engine.predict(prefix: "the")
    #expect(results.count == 3)
    #expect(results[0] == "the")  // Exact match, highest frequency
    #expect(results[1] == "they")
    #expect(results[2] == "them")
}

@Test func predictSingleCharPrefix() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "a")
    #expect(results.count == 3)
    #expect(results[0] == "apple")   // 900
    #expect(results[1] == "application")  // 850
    #expect(results[2] == "apply")   // 800
}

@Test func predictWithFullWord() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "hello")
    #expect(results.count == 1)
    #expect(results[0] == "hello")
}

@Test func predictLongerThanAnyWord() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "applications")
    #expect(results.isEmpty)
}

@Test func bundledDictionaryLoads() {
    // This tests loading from the actual bundle resource
    let engine = PredictionEngine()
    let results = engine.predict(prefix: "the")
    #expect(!results.isEmpty, "Bundled dictionary should have words starting with 'the'")
}
```

```bash
swift test 2>&1 | tail -20
```

- [ ] **Step 4: Implement PredictionEngine (green phase)**

Create `Sources/LucentCore/Control/PredictionEngine.swift`:

```swift
import Foundation

public final class PredictionEngine: Sendable {

    private let sortedWords: [(word: String, frequency: Int)]

    /// Initialize from the bundled words.txt resource.
    public init() {
        if let url = Bundle.module.url(forResource: "words", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            self.sortedWords = PredictionEngine.parse(content)
        } else {
            self.sortedWords = []
        }
    }

    /// Initialize with an explicit word list (for testing).
    public init(words: [(word: String, frequency: Int)]) {
        self.sortedWords = words.sorted { $0.frequency > $1.frequency }
    }

    /// Return up to `maxResults` word completions for the given prefix, sorted by frequency descending.
    public func predict(prefix: String, maxResults: Int = 3) -> [String] {
        guard !prefix.isEmpty else { return [] }

        let lowered = prefix.lowercased()
        var results: [String] = []

        for entry in sortedWords {
            if entry.word.lowercased().hasPrefix(lowered) {
                results.append(entry.word)
                if results.count >= maxResults { break }
            }
        }

        return results
    }

    // MARK: - Parsing

    private static func parse(_ content: String) -> [(word: String, frequency: Int)] {
        var entries: [(word: String, frequency: Int)] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2,
                  let freq = Int(parts[1]) else { continue }

            entries.append((word: String(parts[0]), frequency: freq))
        }

        return entries.sorted { $0.frequency > $1.frequency }
    }
}
```

```bash
swift test 2>&1 | tail -20
```

---

### Task 5: TypingSession (TDD)
**Files:**
- Create: `Tests/LucentCoreTests/TypingSessionTests.swift`
- Create: `Sources/LucentCore/Control/TypingSession.swift`

- [ ] **Step 1: Write TypingSession tests first (red phase)**

Write `Tests/LucentCoreTests/TypingSessionTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import LucentCore

// MARK: - Mock InputController for capturing key presses

/// Captures pressKey calls without posting real CGEvents.
final class MockInputController: @unchecked Sendable {
    var pressedKeys: [(keyCode: UInt16, modifiers: CGEventFlags)] = []

    func pressKey(keyCode: UInt16, modifiers: CGEventFlags = []) {
        pressedKeys.append((keyCode: keyCode, modifiers: modifiers))
    }

    func reset() {
        pressedKeys = []
    }
}

// MARK: - Tests

@Test func typeCharacterAppendsToCurrentWord() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [("hello", 100)])
    let session = TypingSession(mockInputController: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)

    #expect(session.currentWord == "h")
    #expect(mockInput.pressedKeys.count == 1)
    #expect(mockInput.pressedKeys[0].keyCode == 0x04)
}

@Test func typeMultipleCharacters() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(mockInputController: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    let keyI = KeyDefinition(label: "I", keyCode: 0x22, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.typeCharacter(keyI)

    #expect(session.currentWord == "hi")
    #expect(mockInput.pressedKeys.count == 2)
}

@Test func backspaceRemovesLastCharacter() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(mockInputController: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.backspace()

    #expect(session.currentWord == "")
    #expect(mockInput.pressedKeys.last?.keyCode == 0x33)
}

@Test func backspaceOnEmptyWordDoesNothing() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(mockInputController: mockInput, predictionEngine: engine)
    session.start()

    session.backspace()
    #expect(session.currentWord == "")
    #expect(session.buffer == "")
}

@Test func spaceCompletesWord() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(mockInputController: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    let keyI = KeyDefinition(label: "I", keyCode: 0x22, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.typeCharacter(keyI)
    session.space()

    #expect(session.currentWord == "")
    #expect(session.buffer == "hi ")
    #expect(mockInput.pressedKeys.last?.keyCode == 0x31)
}

@Test func enterPostsReturnKey() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(mockInputController: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.enter()

    #expect(session.currentWord == "")
    #expect(session.buffer.contains("\n"))
    #expect(mockInput.pressedKeys.last?.keyCode == 0x24)
}

@Test func acceptPredictionReplacesCurrentWord() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [("hello", 100)])
    let session = TypingSession(mockInputController: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    let keyE = KeyDefinition(label: "E", keyCode: 0x0E, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.typeCharacter(keyE)

    // currentWord is "he", accept "hello"
    mockInput.reset()
    session.acceptPrediction("hello")

    // Should have: 2 backspaces (erase "he") + 5 letter keys (h,e,l,l,o) + 1 space
    #expect(mockInput.pressedKeys.count == 8)
    // First 2 are backspace (0x33)
    #expect(mockInput.pressedKeys[0].keyCode == 0x33)
    #expect(mockInput.pressedKeys[1].keyCode == 0x33)
    // Last is space (0x31)
    #expect(mockInput.pressedKeys.last?.keyCode == 0x31)
    #expect(session.currentWord == "")
    #expect(session.buffer.hasSuffix("hello "))
}

@Test func currentPredictionsReflectsTypedWord() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [
        ("hello", 500), ("help", 400), ("hero", 300), ("world", 200),
    ])
    let session = TypingSession(mockInputController: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    let keyE = KeyDefinition(label: "E", keyCode: 0x0E, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.typeCharacter(keyE)

    let predictions = session.currentPredictions()
    #expect(predictions.count == 3)
    #expect(predictions[0] == "hello")
    #expect(predictions[1] == "help")
    #expect(predictions[2] == "hero")
}

@Test func resetClearsEverything() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(mockInputController: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.reset()

    #expect(session.currentWord == "")
    #expect(session.buffer == "")
    #expect(!session.isActive)
}

@Test func stopDeactivatesSession() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(mockInputController: mockInput, predictionEngine: engine)
    session.start()
    #expect(session.isActive)
    session.stop()
    #expect(!session.isActive)
}
```

```bash
swift test 2>&1 | tail -20
```

- [ ] **Step 2: Implement TypingSession (green phase)**

Create `Sources/LucentCore/Control/TypingSession.swift`:

```swift
import Foundation
import CoreGraphics

/// Manages the text buffer during keyboard mode.
/// Receives resolved key taps, handles special actions, and posts keystrokes to the OS.
public final class TypingSession: @unchecked Sendable {

    public private(set) var buffer: String = ""
    public private(set) var currentWord: String = ""
    public private(set) var isActive: Bool = false

    private let inputController: InputController?
    private let mockInputController: MockInputController?
    private let predictionEngine: PredictionEngine

    /// Production init with real InputController.
    public init(inputController: InputController, predictionEngine: PredictionEngine) {
        self.inputController = inputController
        self.mockInputController = nil
        self.predictionEngine = predictionEngine
    }

    /// Test init with mock InputController.
    init(mockInputController: MockInputController, predictionEngine: PredictionEngine) {
        self.inputController = nil
        self.mockInputController = mockInputController
        self.predictionEngine = predictionEngine
    }

    public func start() {
        isActive = true
        buffer = ""
        currentWord = ""
    }

    public func stop() {
        isActive = false
    }

    public func reset() {
        buffer = ""
        currentWord = ""
        isActive = false
    }

    // MARK: - Typing Actions

    /// Type a single character from a key tap.
    public func typeCharacter(_ key: KeyDefinition) {
        guard isActive else { return }
        let char = key.label.lowercased()
        currentWord.append(char)
        postKey(keyCode: key.keyCode)
    }

    /// Delete the last character.
    public func backspace() {
        guard isActive else { return }
        if !currentWord.isEmpty {
            currentWord.removeLast()
            postKey(keyCode: 0x33)  // Delete key
        } else if !buffer.isEmpty {
            buffer.removeLast()
            postKey(keyCode: 0x33)
        }
    }

    /// Insert a space, completing the current word.
    public func space() {
        guard isActive else { return }
        buffer += currentWord + " "
        currentWord = ""
        postKey(keyCode: 0x31)  // Space key
    }

    /// Insert a newline / return.
    public func enter() {
        guard isActive else { return }
        buffer += currentWord + "\n"
        currentWord = ""
        postKey(keyCode: 0x24)  // Return key
    }

    /// Accept a predicted word, replacing the current partial word.
    public func acceptPrediction(_ word: String) {
        guard isActive else { return }

        // Erase the current partial word
        for _ in 0..<currentWord.count {
            postKey(keyCode: 0x33)  // Backspace
        }

        // Type the full predicted word
        for char in word {
            if let code = VirtualKeyboard.keyCode(for: char) {
                postKey(keyCode: code)
            }
        }

        // Add a space after the word
        postKey(keyCode: 0x31)

        // Update buffer
        buffer += word + " "
        currentWord = ""
    }

    /// Get current word predictions.
    public func currentPredictions() -> [String] {
        return predictionEngine.predict(prefix: currentWord)
    }

    // MARK: - Private

    private func postKey(keyCode: UInt16, modifiers: CGEventFlags = []) {
        if let mock = mockInputController {
            mock.pressKey(keyCode: keyCode, modifiers: modifiers)
        } else {
            inputController?.pressKey(keyCode: keyCode, modifiers: modifiers)
        }
    }
}
```

```bash
swift test 2>&1 | tail -20
```

---

### Task 6: KeyboardOverlay + PredictionBar UI
**Files:**
- Create: `App/UI/KeyboardOverlay.swift`
- Create: `App/UI/PredictionBar.swift`

- [ ] **Step 1: Create KeyboardOverlay.swift**

Create `App/UI/KeyboardOverlay.swift`:

```swift
import SwiftUI
import AppKit
import LucentCore

// MARK: - KeyboardOverlay Panel

final class KeyboardOverlayPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 240),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = contentView
        self.isReleasedWhenClosed = false
    }

    func positionAtBottomCenter(of screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.minY + 20
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// The keyboard portion frame in screen coordinates (excludes prediction bar).
    var keyboardScreenFrame: CGRect {
        let origin = frame.origin
        // Keyboard is the bottom 200pt of the 240pt panel (top 40pt is prediction bar)
        return CGRect(x: origin.x, y: origin.y, width: frame.width, height: 200)
    }
}

// MARK: - Key View

struct KeyView: View {
    let key: KeyDefinition
    let isHovered: Bool
    let isTapped: Bool
    let keyboardWidth: CGFloat
    let keyboardHeight: CGFloat

    var body: some View {
        let w = key.size.width * keyboardWidth
        let h = key.size.height * keyboardHeight

        Text(key.label == "space" ? "________" : key.label)
            .font(.system(size: key.label == "space" ? 14 : 18, weight: isHovered ? .bold : .regular))
            .foregroundColor(.white)
            .frame(width: w - 4, height: h - 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            )
    }

    private var backgroundColor: Color {
        if isTapped { return Color.green.opacity(0.8) }
        if isHovered { return Color.blue.opacity(0.6) }
        return Color.white.opacity(0.15)
    }
}

// MARK: - Keyboard Content View

struct KeyboardContentView: View {
    let keyboard: VirtualKeyboard
    let hoveredKey: KeyDefinition?
    let tappedKey: KeyDefinition?
    let predictions: [String]
    let selectedPredictionIndex: Int?
    let onPredictionTap: (Int) -> Void

    private let keyboardWidth: CGFloat = 600
    private let keyboardHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Prediction bar (40pt)
            PredictionBarView(
                predictions: predictions,
                selectedIndex: selectedPredictionIndex,
                onSelect: onPredictionTap
            )
            .frame(width: keyboardWidth, height: 40)

            // Keyboard layout (200pt)
            ZStack(alignment: .topLeading) {
                // Dark background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.75))

                // Keys
                ForEach(Array(keyboard.keys.enumerated()), id: \.offset) { _, key in
                    KeyView(
                        key: key,
                        isHovered: hoveredKey == key,
                        isTapped: tappedKey == key,
                        keyboardWidth: keyboardWidth,
                        keyboardHeight: keyboardHeight
                    )
                    .position(
                        x: (key.position.x + key.size.width / 2) * keyboardWidth,
                        y: (key.position.y + key.size.height / 2) * keyboardHeight
                    )
                }
            }
            .frame(width: keyboardWidth, height: keyboardHeight)
        }
    }
}
```

- [ ] **Step 2: Create PredictionBar.swift**

Create `App/UI/PredictionBar.swift`:

```swift
import SwiftUI
import LucentCore

struct PredictionBarView: View {
    let predictions: [String]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if predictions.isEmpty {
                Text("Start typing...")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(predictions.enumerated()), id: \.offset) { index, word in
                    PredictionItemView(
                        word: word,
                        isSelected: selectedIndex == index,
                        onSelect: { onSelect(index) }
                    )
                    if index < predictions.count - 1 {
                        Divider()
                            .frame(height: 24)
                            .background(Color.white.opacity(0.2))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
        )
    }
}

struct PredictionItemView: View {
    let word: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(word)
                .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue.opacity(0.4) : Color.clear)
                        .padding(2)
                )
        }
        .buttonStyle(.plain)
    }
}
```

---

### Task 7: InputModeManager + TrackingPipeline Integration
**Files:**
- Modify: `Sources/LucentCore/Control/InputModeManager.swift`
- Modify: `App/TrackingPipeline.swift`

- [ ] **Step 1: Update InputModeManager with keyboard mode support**

Modify `Sources/LucentCore/Control/InputModeManager.swift`:

```swift
import Foundation

public final class InputModeManager: @unchecked Sendable {
    public private(set) var currentMode: InputMode = .normal
    private var scrollHeld = false

    public init() {}

    /// Toggle keyboard mode on/off. Called from Cmd+Shift+K hotkey handler.
    public func toggleKeyboardMode() -> [ModeEvent] {
        if currentMode == .keyboard {
            let previous = currentMode
            currentMode = .normal
            return [.modeChanged(from: previous, to: .normal)]
        } else if currentMode == .normal {
            let previous = currentMode
            currentMode = .keyboard
            return [.modeChanged(from: previous, to: .keyboard)]
        }
        // Can only enter keyboard mode from normal mode
        return []
    }

    public func process(expressions: [DetectedExpression]) -> [ModeEvent] {
        var events: [ModeEvent] = []
        let types = Set(expressions.map(\.type))

        // In keyboard mode, suppress expression-based mode changes
        // but still allow wink actions to pass through
        if currentMode == .keyboard {
            for expression in expressions {
                switch expression.type {
                case .winkLeft, .winkRight:
                    events.append(.actionTriggered(expression.type))
                default:
                    break  // Suppress scroll, dictation, command palette triggers
                }
            }
            return events
        }

        // Scroll: hold-to-activate, release to deactivate
        if currentMode == .scroll && !types.contains(.mouthOpen) {
            currentMode = .normal
            scrollHeld = false
            events.append(.modeChanged(from: .scroll, to: .normal))
        }

        for expression in expressions {
            switch expression.type {
            case .mouthOpen:
                if currentMode == .normal {
                    currentMode = .scroll
                    scrollHeld = true
                    events.append(.modeChanged(from: .normal, to: .scroll))
                }
            case .smile:
                if currentMode == .dictation {
                    currentMode = .normal
                    events.append(.modeChanged(from: .dictation, to: .normal))
                } else if currentMode == .normal {
                    currentMode = .dictation
                    events.append(.modeChanged(from: .normal, to: .dictation))
                }
            case .browRaise:
                if currentMode == .commandPalette {
                    currentMode = .normal
                    events.append(.modeChanged(from: .commandPalette, to: .normal))
                } else if currentMode == .normal {
                    currentMode = .commandPalette
                    events.append(.modeChanged(from: .normal, to: .commandPalette))
                }
            case .winkLeft, .winkRight:
                events.append(.actionTriggered(expression.type))
            }
        }
        return events
    }

    public func handleFaceLost() -> [ModeEvent] {
        if currentMode != .normal {
            let previous = currentMode
            currentMode = .normal
            scrollHeld = false
            return [.modeChanged(from: previous, to: .normal)]
        }
        return []
    }
}
```

```bash
swift build 2>&1 | head -30
```

- [ ] **Step 2: Update TrackingPipeline with keyboard mode handling**

Modify `App/TrackingPipeline.swift`. The full updated file:

```swift
import Foundation
import AVFoundation
import LucentCore

@MainActor
public final class TrackingPipeline: ObservableObject {
    @Published public var trackingState: TrackingState = .idle
    @Published public var isEnabled = false
    @Published public var currentCursorPosition = GazePoint.zero
    @Published public var currentMode: InputMode = .normal
    @Published public var activeExpressions: [DetectedExpression] = []
    @Published public var faceConfidence: Float = 0
    @Published public var handDetected: Bool = false
    @Published public var activeGesture: GestureType? = nil
    @Published public var handGesturesEnabled: Bool = true
    @Published public var handCount: Int = 0

    // Keyboard mode state
    @Published public var keyboardModeActive: Bool = false
    @Published public var hoveredKey: KeyDefinition? = nil
    @Published public var currentTypedWord: String = ""
    @Published public var predictions: [String] = []
    @Published public var selectedPredictionIndex: Int? = nil

    private var isDragging: Bool = false
    private var isPointActive: Bool = false

    private let cameraManager = CameraManager()
    private let frameProcessor: FrameProcessor
    private let blinkDetector = BlinkDetector()
    private let cursorSmoother: CursorSmoother
    private let inputController = InputController()
    private let modeManager = InputModeManager()
    private let headTiltProcessor = HeadTiltProcessor()
    private var calibrationProfile: CalibrationProfile?

    // Keyboard mode components
    private let tapDetector = TapDetector()
    private let keyResolver = KeyResolver()
    private let predictionEngine = PredictionEngine()
    private lazy var typingSession: TypingSession = {
        TypingSession(inputController: inputController, predictionEngine: predictionEngine)
    }()

    private var faceLostTime: Double?
    private let faceLostTimeout: Double = 0.5
    private var lowConfidenceCount = 0

    public var cameraDeviceID: String { cameraManager.currentDeviceID ?? "unknown" }

    /// Screen-space frame of the keyboard overlay, set by the UI layer.
    public var keyboardFrame: CGRect = CGRect(x: 0, y: 0, width: 600, height: 200)

    public init() {
        let gazeEstimator = MockGazeEstimator()
        self.frameProcessor = FrameProcessor(gazeEstimator: gazeEstimator)
        self.cursorSmoother = CursorSmoother()
        self.calibrationProfile = try? CalibrationProfile.load()
    }

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
        currentMode = .normal
        exitKeyboardMode()
    }

    public func toggle() throws { if isEnabled { stop() } else { try start() } }

    public func setCalibrationProfile(_ profile: CalibrationProfile) {
        self.calibrationProfile = profile
        try? profile.save()
        if isEnabled { trackingState = .tracking }
    }

    // MARK: - Keyboard Mode

    public func toggleKeyboardMode() {
        let events = modeManager.toggleKeyboardMode()
        currentMode = modeManager.currentMode
        for event in events {
            handleModeEvent(event)
        }
    }

    private func enterKeyboardMode() {
        keyboardModeActive = true
        typingSession.start()
        tapDetector.reset()
        hoveredKey = nil
        currentTypedWord = ""
        predictions = []
        selectedPredictionIndex = nil
    }

    private func exitKeyboardMode() {
        keyboardModeActive = false
        typingSession.stop()
        tapDetector.reset()
        hoveredKey = nil
        currentTypedWord = ""
        predictions = []
        selectedPredictionIndex = nil
    }
}

extension TrackingPipeline: CameraManagerDelegate {
    nonisolated public func cameraManager(_ manager: CameraManager, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        let time = CMTimeGetSeconds(timestamp)
        guard let result = frameProcessor.process(pixelBuffer: pixelBuffer, timestamp: time) else {
            Task { @MainActor in handleFaceLost(at: time) }
            return
        }
        Task { @MainActor in handleFrame(result) }
    }

    nonisolated public func cameraManager(_ manager: CameraManager, didFailWithError error: Error) {
        Task { @MainActor in trackingState = .paused(reason: .cameraDisconnected) }
    }
}

extension TrackingPipeline {
    private func handleFrame(_ result: FrameProcessor.FrameResult) {
        faceLostTime = nil
        faceConfidence = result.confidence
        activeExpressions = result.expressions

        // Update hand tracking state
        handDetected = !result.hands.isEmpty
        handCount = result.hands.count

        if result.confidence < 0.5 {
            lowConfidenceCount += 1
            if lowConfidenceCount > 30 { trackingState = .paused(reason: .poorLighting) }
        } else { lowConfidenceCount = 0 }

        guard let profile = calibrationProfile else {
            trackingState = .detecting
            return
        }
        trackingState = .tracking

        let modeEvents = modeManager.process(expressions: result.expressions)
        currentMode = modeManager.currentMode

        for event in modeEvents {
            handleModeEvent(event)
        }

        switch currentMode {
        case .normal, .commandPalette:
            blinkDetector.isEnabled = true
            headTiltProcessor.isEnabled = (currentMode == .normal)
            handleNormalTracking(result, profile: profile)
        case .scroll:
            blinkDetector.isEnabled = false
            headTiltProcessor.isEnabled = false
            handleScrollMode(result, profile: profile)
        case .dictation:
            blinkDetector.isEnabled = false
            headTiltProcessor.isEnabled = false
            handleWinkClicks(result)
        case .keyboard:
            blinkDetector.isEnabled = true  // Needed for prediction selection
            headTiltProcessor.isEnabled = false
            handleKeyboardMode(result, profile: profile)
        }

        // Process hand gestures only when NOT in keyboard mode
        if currentMode != .keyboard {
            handleGestureEvents(result.gestures, cursorPosition: currentCursorPosition)
        }
    }

    // MARK: - Keyboard Mode Frame Handling

    private func handleKeyboardMode(_ result: FrameProcessor.FrameResult, profile: CalibrationProfile) {
        // Eye tracking continues for cursor (prediction bar selection)
        let screenPoint = profile.mapToScreen(result.rawGaze)
        let smoothed = cursorSmoother.smooth(screenPoint)
        currentCursorPosition = smoothed
        inputController.moveCursor(to: smoothed)

        // Update prediction bar selection based on gaze position
        updatePredictionSelection(cursorPosition: smoothed)

        // Process hand data for typing
        guard let handData = result.hands.first else {
            hoveredKey = nil
            return
        }

        // Check for space gesture: thumb extended, all others curled
        if handData.fingerStates[.thumb] == .extended &&
           handData.fingerStates[.index] == .curled &&
           handData.fingerStates[.middle] == .curled &&
           handData.fingerStates[.ring] == .curled &&
           handData.fingerStates[.little] == .curled {
            typingSession.space()
            currentTypedWord = typingSession.currentWord
            predictions = typingSession.currentPredictions()
            return
        }

        // Check for backspace: reuse swipe-left gesture detection
        for gesture in result.gestures {
            if gesture.type == .swipeLeft && gesture.state == .discrete {
                typingSession.backspace()
                currentTypedWord = typingSession.currentWord
                predictions = typingSession.currentPredictions()
                return
            }
            // Fist gesture = enter
            if gesture.type == .fist && gesture.state == .began {
                typingSession.enter()
                currentTypedWord = typingSession.currentWord
                predictions = typingSession.currentPredictions()
                return
            }
        }

        // Update hovered key from fingertip position
        if let indexTip = handData.landmarks[.indexTip] {
            let screenPos = CGPoint(
                x: Double(indexTip.x) * profile.screenWidth,
                y: Double(indexTip.y) * profile.screenHeight
            )
            hoveredKey = keyResolver.resolve(
                fingertipScreenPosition: screenPos,
                keyboardFrame: keyboardFrame
            )
        }

        // Run tap detection
        if let tapEvent = tapDetector.update(handData: handData) {
            let screenPos = CGPoint(
                x: Double(tapEvent.fingertipPosition.x) * profile.screenWidth,
                y: Double(tapEvent.fingertipPosition.y) * profile.screenHeight
            )
            if let key = keyResolver.resolve(fingertipScreenPosition: screenPos, keyboardFrame: keyboardFrame) {
                if key.label != "space" {
                    typingSession.typeCharacter(key)
                    currentTypedWord = typingSession.currentWord
                    predictions = typingSession.currentPredictions()
                }
            }
        }

        // Handle blink for prediction acceptance
        let avgEAR = (result.leftEAR + result.rightEAR) / 2.0
        let clickEvents = blinkDetector.update(ear: avgEAR, timestamp: result.timestamp)
        for event in clickEvents {
            switch event {
            case .leftClick:
                if let idx = selectedPredictionIndex, idx < predictions.count {
                    typingSession.acceptPrediction(predictions[idx])
                    currentTypedWord = typingSession.currentWord
                    predictions = typingSession.currentPredictions()
                    selectedPredictionIndex = nil
                }
            default:
                break
            }
        }

        // Wink actions still pass through
        handleWinkClicks(result)
    }

    private func updatePredictionSelection(cursorPosition: GazePoint) {
        guard !predictions.isEmpty else {
            selectedPredictionIndex = nil
            return
        }

        // Prediction bar is at the top of the keyboard panel
        // Each prediction item spans 1/predictions.count of the width
        let barX = keyboardFrame.origin.x
        let barY = keyboardFrame.origin.y + keyboardFrame.height  // Above the keyboard
        let barWidth = keyboardFrame.width
        let barHeight: CGFloat = 40

        let cursorX = CGFloat(cursorPosition.x)
        let cursorY = CGFloat(cursorPosition.y)

        // Check if cursor is within prediction bar bounds
        if cursorX >= barX && cursorX <= barX + barWidth &&
           cursorY >= barY && cursorY <= barY + barHeight {
            let relativeX = (cursorX - barX) / barWidth
            let idx = Int(relativeX * CGFloat(predictions.count))
            selectedPredictionIndex = min(idx, predictions.count - 1)
        } else {
            selectedPredictionIndex = nil
        }
    }

    private func handleNormalTracking(_ result: FrameProcessor.FrameResult, profile: CalibrationProfile) {
        // During point gesture, fingertip controls cursor -- skip eye-gaze cursor
        if !isPointActive {
            let screenPoint = profile.mapToScreen(result.rawGaze)
            let smoothed = cursorSmoother.smooth(screenPoint)
            let tiltOffset = headTiltProcessor.process(rollDegrees: result.headRoll)
            let final = GazePoint(x: smoothed.x + tiltOffset.x, y: smoothed.y + tiltOffset.y)
            currentCursorPosition = final

            if isDragging {
                inputController.dragMove(to: final)
            } else {
                inputController.moveCursor(to: final)
            }
        }

        let avgEAR = (result.leftEAR + result.rightEAR) / 2.0
        let clickEvents = blinkDetector.update(ear: avgEAR, timestamp: result.timestamp)
        for event in clickEvents {
            switch event {
            case .leftClick: inputController.leftClick(at: currentCursorPosition)
            case .rightClick: inputController.rightClick(at: currentCursorPosition)
            case .doubleClick: inputController.doubleClick(at: currentCursorPosition)
            }
        }
        handleWinkClicks(result)
    }

    private func handleScrollMode(_ result: FrameProcessor.FrameResult, profile: CalibrationProfile) {
        let screenPoint = profile.mapToScreen(result.rawGaze)
        let vertCenter = profile.screenHeight / 2.0
        let vertDead = profile.screenHeight * 0.1
        let vertOffset = screenPoint.y - vertCenter
        var scrollY: Int32 = 0
        if abs(vertOffset) > vertDead {
            let speed = (abs(vertOffset) - vertDead) / (profile.screenHeight / 2.0)
            scrollY = Int32(speed * -10.0 * (vertOffset > 0 ? 1 : -1))
        }
        let horizCenter = profile.screenWidth / 2.0
        let horizDead = profile.screenWidth * 0.1
        let horizOffset = screenPoint.x - horizCenter
        var scrollX: Int32 = 0
        if abs(horizOffset) > horizDead {
            let speed = (abs(horizOffset) - horizDead) / (profile.screenWidth / 2.0)
            scrollX = Int32(speed * 10.0 * (horizOffset > 0 ? 1 : -1))
        }
        if scrollY != 0 || scrollX != 0 { inputController.scroll(deltaY: scrollY, deltaX: scrollX) }
        handleWinkClicks(result)
    }

    private func handleWinkClicks(_ result: FrameProcessor.FrameResult) {
        for expression in result.expressions {
            switch expression.type {
            case .winkLeft: inputController.rightClick(at: currentCursorPosition)
            case .winkRight: inputController.doubleClick(at: currentCursorPosition)
            default: break
            }
        }
    }

    private func handleModeEvent(_ event: ModeEvent) {
        switch event {
        case .modeChanged(_, let to):
            switch to {
            case .dictation: inputController.triggerDictation()
            case .commandPalette: inputController.triggerSpotlight()
            case .keyboard: enterKeyboardMode()
            case .normal:
                if keyboardModeActive { exitKeyboardMode() }
            case .scroll: break
            }
        case .actionTriggered: break
        case .keyboardAction: break
        }
    }

    private func handleFaceLost(at time: Double) {
        if faceLostTime == nil { faceLostTime = time }
        if let lost = faceLostTime, time - lost > faceLostTimeout {
            trackingState = .paused(reason: .faceLost)
            let events = modeManager.handleFaceLost()
            if !events.isEmpty {
                currentMode = .normal
                if keyboardModeActive { exitKeyboardMode() }
            }
        }
    }

    private func handleGestureEvents(_ gestures: [GestureEvent], cursorPosition: GazePoint) {
        guard handGesturesEnabled else { return }

        for gesture in gestures {
            activeGesture = gesture.type

            switch gesture.type {
            case .swipeLeft:
                guard gesture.state == .discrete else { continue }
                inputController.switchDesktop(direction: .left)

            case .swipeRight:
                guard gesture.state == .discrete else { continue }
                inputController.switchDesktop(direction: .right)

            case .swipeUp:
                guard gesture.state == .discrete else { continue }
                inputController.triggerMissionControl()

            case .swipeDown:
                guard gesture.state == .discrete else { continue }
                inputController.triggerExpose()

            case .pinch:
                switch gesture.state {
                case .changed(let distance):
                    if distance < 0.015 {
                        inputController.zoom(direction: .zoomIn)
                    } else {
                        inputController.zoom(direction: .zoomOut)
                    }
                case .began, .ended, .discrete:
                    break
                }

            case .fist:
                switch gesture.state {
                case .began:
                    isDragging = true
                    inputController.startDrag(at: cursorPosition)
                case .ended:
                    isDragging = false
                    inputController.endDrag(at: cursorPosition)
                case .changed, .discrete:
                    break
                }

            case .point:
                switch gesture.state {
                case .began:
                    isPointActive = true
                case .changed(let encodedPosition):
                    let y = encodedPosition / 10000.0
                    let x = encodedPosition - (y.rounded(.down) * 10000.0)
                    if let profile = calibrationProfile {
                        let screenPoint = GazePoint(
                            x: x * profile.screenWidth,
                            y: y * profile.screenHeight
                        )
                        currentCursorPosition = screenPoint
                        if isDragging {
                            inputController.dragMove(to: screenPoint)
                        } else {
                            inputController.moveCursor(to: screenPoint)
                        }
                    }
                case .ended:
                    isPointActive = false
                case .discrete:
                    break
                }

            case .openPalm:
                guard gesture.state == .discrete else { continue }
                handGesturesEnabled.toggle()
                activeGesture = nil
            }
        }

        if gestures.allSatisfy({ $0.state == .discrete || $0.state == .ended }) {
            activeGesture = nil
        }
    }
}
```

```bash
swift build 2>&1 | head -30
```

---

### Task 8: AppState + MenuBar Updates
**Files:**
- Modify: `App/AppState.swift`
- Modify: `App/UI/MenuBarView.swift`

- [ ] **Step 1: Update AppState with keyboard mode hotkey and state**

Modify `App/AppState.swift`:

```swift
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
    @Published public var showHUD: Bool
    @Published public var hudExpanded: Bool
    @Published public var handGesturesEnabled: Bool
    @Published public var keyboardModeEnabled: Bool

    private var hotkeyRef: EventHotKeyRef?
    private var hudHotkeyRef: EventHotKeyRef?
    private var keyboardHotkeyRef: EventHotKeyRef?

    public init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.showHUD = UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true
        self.hudExpanded = UserDefaults.standard.bool(forKey: "hudExpanded")
        self.handGesturesEnabled = UserDefaults.standard.object(forKey: "handGesturesEnabled") as? Bool ?? true
        self.keyboardModeEnabled = UserDefaults.standard.object(forKey: "keyboardModeEnabled") as? Bool ?? false
        registerGlobalHotkeys()
    }

    public func toggleTracking() {
        do { try pipeline.toggle() } catch { print("Failed to toggle tracking: \(error)") }
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    public func toggleHUDExpanded() {
        hudExpanded.toggle()
        UserDefaults.standard.set(hudExpanded, forKey: "hudExpanded")
    }

    public func toggleHandGestures() {
        handGesturesEnabled.toggle()
        pipeline.handGesturesEnabled = handGesturesEnabled
        UserDefaults.standard.set(handGesturesEnabled, forKey: "handGesturesEnabled")
    }

    public func toggleKeyboardMode() {
        guard keyboardModeEnabled else { return }
        pipeline.toggleKeyboardMode()
    }

    public func setKeyboardModeEnabled(_ enabled: Bool) {
        keyboardModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "keyboardModeEnabled")
        if !enabled && pipeline.keyboardModeActive {
            pipeline.toggleKeyboardMode()  // Exit keyboard mode if disabling
        }
    }

    public var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { print("Failed to set launch at login: \(error)") }
        }
    }

    private func registerGlobalHotkeys() {
        // Hotkey 1: Cmd+Shift+L -- Toggle tracking
        var trackingHotKeyID = EventHotKeyID()
        trackingHotKeyID.signature = OSType(0x4C554345)
        trackingHotKeyID.id = 1
        var ref1: EventHotKeyRef?
        RegisterEventHotKey(0x25, UInt32(cmdKey | shiftKey), trackingHotKeyID, GetApplicationEventTarget(), 0, &ref1)
        hotkeyRef = ref1

        // Hotkey 2: Cmd+Shift+H -- Toggle HUD
        var hudHotKeyID = EventHotKeyID()
        hudHotKeyID.signature = OSType(0x4C554345)
        hudHotKeyID.id = 2
        var ref2: EventHotKeyRef?
        RegisterEventHotKey(0x04, UInt32(cmdKey | shiftKey), hudHotKeyID, GetApplicationEventTarget(), 0, &ref2)
        hudHotkeyRef = ref2

        // Hotkey 3: Cmd+Shift+K -- Toggle keyboard mode
        var keyboardHotKeyID = EventHotKeyID()
        keyboardHotKeyID.signature = OSType(0x4C554345)
        keyboardHotKeyID.id = 3
        var ref3: EventHotKeyRef?
        RegisterEventHotKey(0x28, UInt32(cmdKey | shiftKey), keyboardHotKeyID, GetApplicationEventTarget(), 0, &ref3)
        keyboardHotkeyRef = ref3

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                            EventParamType(typeEventHotKeyID), nil,
                            MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            switch hotKeyID.id {
            case 1: NotificationCenter.default.post(name: .toggleTracking, object: nil)
            case 2: NotificationCenter.default.post(name: .toggleHUD, object: nil)
            case 3: NotificationCenter.default.post(name: .toggleKeyboard, object: nil)
            default: break
            }
            return noErr
        }, 1, &eventType, nil, nil)

        NotificationCenter.default.addObserver(forName: .toggleTracking, object: nil, queue: .main) { [weak self] _ in self?.toggleTracking() }
        NotificationCenter.default.addObserver(forName: .toggleHUD, object: nil, queue: .main) { [weak self] _ in self?.toggleHUDExpanded() }
        NotificationCenter.default.addObserver(forName: .toggleKeyboard, object: nil, queue: .main) { [weak self] _ in self?.toggleKeyboardMode() }
    }
}

extension Notification.Name {
    static let toggleTracking = Notification.Name("com.lucent.toggleTracking")
    static let toggleHUD = Notification.Name("com.lucent.toggleHUD")
    static let toggleKeyboard = Notification.Name("com.lucent.toggleKeyboard")
}
```

- [ ] **Step 2: Update MenuBarView with keyboard mode toggle and indicator**

Modify `App/UI/MenuBarView.swift`:

```swift
import SwiftUI
import LucentCore

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.headline)
            }
            if appState.pipeline.currentMode != .normal {
                HStack(spacing: 4) {
                    Image(systemName: modeIcon).font(.system(size: 11))
                    Text(modeName).font(.caption)
                }.foregroundColor(.blue)
            }
            Divider()
            Toggle("Eye Tracking", isOn: Binding(
                get: { appState.pipeline.isEnabled },
                set: { _ in appState.toggleTracking() }))
            Toggle("Show HUD", isOn: Binding(
                get: { appState.showHUD },
                set: { appState.showHUD = $0; UserDefaults.standard.set($0, forKey: "showHUD") }))
            Toggle("Hand Gestures", isOn: Binding(
                get: { appState.handGesturesEnabled },
                set: { _ in appState.toggleHandGestures() }))
            Toggle("Virtual Keyboard", isOn: Binding(
                get: { appState.keyboardModeEnabled },
                set: { appState.setKeyboardModeEnabled($0) }))
            Button("Quick Recalibrate") { appState.showCalibration = true }
                .disabled(!appState.pipeline.isEnabled)
            Divider()
            Button("Settings...") { appState.showSettings = true; NSApp.activate(ignoringOtherApps: true) }
                .keyboardShortcut(",", modifiers: .command)
            Button("Quit Lucent") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }.padding(12).frame(width: 220)
    }

    private var statusColor: Color {
        switch appState.pipeline.trackingState {
        case .tracking: .green; case .detecting: .yellow; case .calibrating: .blue; case .paused: .red; case .idle: .gray
        }
    }
    private var statusText: String {
        switch appState.pipeline.trackingState {
        case .tracking: "Tracking Active"; case .detecting: "Detecting Face"; case .calibrating: "Calibrating"
        case .paused(let r): switch r { case .faceLost: "Face Lost"; case .poorLighting: "Poor Lighting"; case .cameraDisconnected: "Camera Disconnected"; case .userPaused: "Paused" }
        case .idle: "Idle"
        }
    }
    private var modeIcon: String {
        switch appState.pipeline.currentMode {
        case .normal: "eye"
        case .scroll: "scroll"
        case .dictation: "mic"
        case .commandPalette: "magnifyingglass"
        case .keyboard: "keyboard"
        }
    }
    private var modeName: String {
        switch appState.pipeline.currentMode {
        case .normal: "Normal"
        case .scroll: "Scroll Mode"
        case .dictation: "Dictation"
        case .commandPalette: "Command Palette"
        case .keyboard: "Keyboard Mode"
        }
    }
}
```

```bash
swift build 2>&1 | head -30
```

---

### Task 9: Final Integration + Verification
**Files:**
- All previously created/modified files

- [ ] **Step 1: Run full test suite**

```bash
swift test 2>&1 | tail -40
```

- [ ] **Step 2: Run build to verify no compilation errors**

```bash
swift build 2>&1 | tail -20
```

- [ ] **Step 3: Verify all new files exist in correct locations**

```bash
ls -la Sources/LucentCore/Models/VirtualKeyboard.swift
ls -la Sources/LucentCore/Tracking/TapDetector.swift
ls -la Sources/LucentCore/Tracking/KeyResolver.swift
ls -la Sources/LucentCore/Control/PredictionEngine.swift
ls -la Sources/LucentCore/Control/TypingSession.swift
ls -la Sources/LucentCore/Resources/words.txt
ls -la App/UI/KeyboardOverlay.swift
ls -la App/UI/PredictionBar.swift
ls -la Tests/LucentCoreTests/VirtualKeyboardTests.swift
ls -la Tests/LucentCoreTests/TapDetectorTests.swift
ls -la Tests/LucentCoreTests/KeyResolverTests.swift
ls -la Tests/LucentCoreTests/PredictionEngineTests.swift
ls -la Tests/LucentCoreTests/TypingSessionTests.swift
```

- [ ] **Step 4: Manual integration smoke test**

Run the app and verify:
1. Cmd+Shift+K toggles keyboard overlay on/off
2. Keyboard overlay appears at bottom of screen with QWERTY layout
3. Hand hover highlights keys
4. Finger tap fires keystrokes into the focused text field
5. Prediction bar shows word completions
6. Eye gaze selects predictions, blink accepts
7. Swipe left = backspace, thumb tap = space, fist = enter
8. Exiting keyboard mode (Cmd+Shift+K again) hides overlay and restores normal tracking
9. Face expressions (wink) still work during keyboard mode
