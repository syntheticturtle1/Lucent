# Lucent Phase 2: Face Expressions + HUD Overlay — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add facial expression recognition (wink, smile, brow raise, mouth open), input mode switching, head tilt fine cursor, and a floating HUD overlay to Lucent.

**Architecture:** Geometric ratios computed from existing Vision landmarks detect expressions. An InputModeManager state machine routes expressions to mode switches or actions. A HeadTiltProcessor adds fine cursor offset. A floating NSPanel HUD provides real-time feedback with three layers (minimal pill, expanded dashboard, contextual toasts).

**Tech Stack:** Swift, SwiftUI, Apple Vision (existing landmarks), CGEvent (scroll/key events), NSPanel, Carbon.HIToolbox (hotkey)

**Spec:** `docs/superpowers/specs/2026-04-09-lucent-phase2-design.md`

---

## File Structure

**New files:**
```
Sources/LucentCore/Models/InputMode.swift
Sources/LucentCore/Tracking/ExpressionDetector.swift
Sources/LucentCore/Control/InputModeManager.swift
Sources/LucentCore/Control/HeadTiltProcessor.swift
Tests/LucentCoreTests/ExpressionDetectorTests.swift
Tests/LucentCoreTests/InputModeManagerTests.swift
Tests/LucentCoreTests/HeadTiltProcessorTests.swift
App/UI/HUDPanel.swift
App/UI/HUDMinimalView.swift
App/UI/HUDExpandedView.swift
App/UI/HUDToastView.swift
```

**Modified files:**
```
Sources/LucentCore/Tracking/FaceLandmarkDetector.swift  (expand FaceData)
Sources/LucentCore/Tracking/BlinkDetector.swift          (add isEnabled)
Sources/LucentCore/Control/InputController.swift         (add scroll + pressKey)
Sources/LucentCore/Camera/FrameProcessor.swift           (add expressions + headRoll)
App/TrackingPipeline.swift                                (integrate everything)
App/AppState.swift                                        (add HUD state + hotkey)
App/UI/MenuBarView.swift                                  (add mode + HUD toggle)
```

---

## Task 1: InputMode Models

**Files:**
- Create: `Sources/LucentCore/Models/InputMode.swift`

- [ ] **Step 1: Create InputMode models**

```swift
// Sources/LucentCore/Models/InputMode.swift
import Foundation

public enum InputMode: String, Codable, Sendable, CaseIterable {
    case normal
    case scroll
    case dictation
    case commandPalette
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

/// Stores per-expression detection configuration.
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

/// Events emitted by InputModeManager when modes change.
public enum ModeEvent: Equatable, Sendable {
    case modeChanged(from: InputMode, to: InputMode)
    case actionTriggered(ExpressionType)
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LucentCore/Models/InputMode.swift
git commit -m "feat: add InputMode, ExpressionType, DetectedExpression, ExpressionConfig models"
```

---

## Task 2: Expand FaceData with Mouth and Brow Landmarks

**Files:**
- Modify: `Sources/LucentCore/Tracking/FaceLandmarkDetector.swift`

- [ ] **Step 1: Add mouth and brow fields to FaceData**

Add four new fields to the `FaceData` struct:

```swift
public struct FaceData: Sendable {
    public let faceBounds: CGRect
    public let leftEyePoints: [CGPoint]
    public let rightEyePoints: [CGPoint]
    public let leftPupil: CGPoint
    public let rightPupil: CGPoint
    public let outerLipsPoints: [CGPoint]
    public let innerLipsPoints: [CGPoint]
    public let leftBrowPoints: [CGPoint]
    public let rightBrowPoints: [CGPoint]
    public let confidence: Float
}
```

- [ ] **Step 2: Extract new landmarks in detect()**

In the `detect(in:)` method, after the existing `guard let` for eyes and pupils, add extraction of mouth and brow landmarks. Change the guard to also require these regions:

```swift
guard let leftEye = landmarks.leftEye,
      let rightEye = landmarks.rightEye,
      let leftPupil = landmarks.leftPupil,
      let rightPupil = landmarks.rightPupil else {
    return nil
}

let outerLips = landmarks.outerLips
let innerLips = landmarks.innerLips
let leftBrow = landmarks.leftEyebrow
let rightBrow = landmarks.rightEyebrow
```

Then update the FaceData initializer to include the new fields:

```swift
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
    outerLipsPoints: outerLips.map { convertPoints($0) } ?? [],
    innerLipsPoints: innerLips.map { convertPoints($0) } ?? [],
    leftBrowPoints: leftBrow.map { convertPoints($0) } ?? [],
    rightBrowPoints: rightBrow.map { convertPoints($0) } ?? [],
    confidence: face.confidence
)
```

- [ ] **Step 3: Verify build and tests**

Run: `swift test`
Expected: All 22 existing tests still pass (FaceData is only consumed by FrameProcessor which just reads eye fields)

- [ ] **Step 4: Commit**

```bash
git add Sources/LucentCore/Tracking/FaceLandmarkDetector.swift
git commit -m "feat: expand FaceData with mouth and brow landmark regions"
```

---

## Task 3: ExpressionDetector (TDD)

**Files:**
- Create: `Sources/LucentCore/Tracking/ExpressionDetector.swift`
- Create: `Tests/LucentCoreTests/ExpressionDetectorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/LucentCoreTests/ExpressionDetectorTests.swift
import Testing
import CoreGraphics
@testable import LucentCore

// MARK: - Metric Computation Tests

@Test func mouthAspectRatioOpenMouth() {
    // Wide open mouth: tall inner lips
    let inner = makeRectPoints(cx: 0.5, cy: 0.5, width: 0.06, height: 0.04)
    let mar = ExpressionDetector.mouthOpenRatio(innerLipsPoints: inner)
    #expect(mar > 0.5)
}

@Test func mouthAspectRatioClosedMouth() {
    // Closed mouth: very thin inner lips
    let inner = makeRectPoints(cx: 0.5, cy: 0.5, width: 0.06, height: 0.002)
    let mar = ExpressionDetector.mouthOpenRatio(innerLipsPoints: inner)
    #expect(mar < 0.1)
}

@Test func smileRatioWhenSmiling() {
    // Wide outer lips (smile): much wider than tall
    let outer = makeRectPoints(cx: 0.5, cy: 0.5, width: 0.1, height: 0.02)
    let ratio = ExpressionDetector.smileRatio(outerLipsPoints: outer)
    #expect(ratio > 3.0)
}

@Test func smileRatioNeutral() {
    // Neutral mouth: roughly equal proportions
    let outer = makeRectPoints(cx: 0.5, cy: 0.5, width: 0.06, height: 0.03)
    let ratio = ExpressionDetector.smileRatio(outerLipsPoints: outer)
    #expect(ratio < 3.0)
}

@Test func browHeightRatioRaised() {
    // Brow far from eye = raised
    let browPoints = [CGPoint(x: 0.4, y: 0.30), CGPoint(x: 0.45, y: 0.28),
                      CGPoint(x: 0.5, y: 0.27), CGPoint(x: 0.55, y: 0.28)]
    let eyeTop: CGFloat = 0.40
    let ratio = ExpressionDetector.browHeight(browPoints: browPoints, eyeTopY: eyeTop)
    #expect(ratio > 0.08)
}

@Test func browHeightRatioNeutral() {
    // Brow close to eye = neutral
    let browPoints = [CGPoint(x: 0.4, y: 0.38), CGPoint(x: 0.45, y: 0.37),
                      CGPoint(x: 0.5, y: 0.36), CGPoint(x: 0.55, y: 0.37)]
    let eyeTop: CGFloat = 0.40
    let ratio = ExpressionDetector.browHeight(browPoints: browPoints, eyeTopY: eyeTop)
    #expect(ratio < 0.05)
}

@Test func headRollAngleLevel() {
    let roll = ExpressionDetector.headRoll(leftPupil: CGPoint(x: 0.4, y: 0.5),
                                            rightPupil: CGPoint(x: 0.6, y: 0.5))
    #expect(abs(roll) < 1.0) // degrees
}

@Test func headRollAngleTilted() {
    // Right pupil higher than left = tilted right
    let roll = ExpressionDetector.headRoll(leftPupil: CGPoint(x: 0.4, y: 0.5),
                                            rightPupil: CGPoint(x: 0.6, y: 0.45))
    #expect(roll > 5.0) // positive = tilted right
}

// MARK: - Expression Detection Tests

@Test func winkLeftDetected() {
    let detector = ExpressionDetector()
    // Calibrate baseline with neutral face
    feedNeutralFrames(detector: detector, count: 60)
    // Now left eye closed, right open
    var detected: [DetectedExpression] = []
    for i in 0..<10 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        detected += detector.update(leftEAR: 0.05, rightEAR: 0.3,
                                     smileRatio: 2.0, browHeight: 0.03,
                                     mouthOpenRatio: 0.05, headRoll: 0.0,
                                     timestamp: t)
    }
    #expect(detected.contains(where: { $0.type == .winkLeft }))
}

@Test func winkNotDetectedDuringBlink() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    // Both eyes closed = blink, not wink
    var detected: [DetectedExpression] = []
    for i in 0..<10 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        detected += detector.update(leftEAR: 0.05, rightEAR: 0.05,
                                     smileRatio: 2.0, browHeight: 0.03,
                                     mouthOpenRatio: 0.05, headRoll: 0.0,
                                     timestamp: t)
    }
    #expect(!detected.contains(where: { $0.type == .winkLeft }))
    #expect(!detected.contains(where: { $0.type == .winkRight }))
}

@Test func smileDetectedAfterHold() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    // Smile for 500ms+
    var detected: [DetectedExpression] = []
    for i in 0..<20 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        detected += detector.update(leftEAR: 0.3, rightEAR: 0.3,
                                     smileRatio: 4.0, browHeight: 0.03,
                                     mouthOpenRatio: 0.05, headRoll: 0.0,
                                     timestamp: t)
    }
    #expect(detected.contains(where: { $0.type == .smile }))
}

@Test func browRaiseDetected() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    var detected: [DetectedExpression] = []
    for i in 0..<15 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        detected += detector.update(leftEAR: 0.3, rightEAR: 0.3,
                                     smileRatio: 2.0, browHeight: 0.10,
                                     mouthOpenRatio: 0.05, headRoll: 0.0,
                                     timestamp: t)
    }
    #expect(detected.contains(where: { $0.type == .browRaise }))
}

@Test func mouthOpenDetected() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    var detected: [DetectedExpression] = []
    for i in 0..<15 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        detected += detector.update(leftEAR: 0.3, rightEAR: 0.3,
                                     smileRatio: 2.0, browHeight: 0.03,
                                     mouthOpenRatio: 0.6, headRoll: 0.0,
                                     timestamp: t)
    }
    #expect(detected.contains(where: { $0.type == .mouthOpen }))
}

@Test func cooldownPreventsRapidRefire() {
    let detector = ExpressionDetector()
    feedNeutralFrames(detector: detector, count: 60)
    // First wink
    var first: [DetectedExpression] = []
    for i in 0..<10 {
        let t = 2.0 + Double(i) * (1.0/30.0)
        first += detector.update(leftEAR: 0.05, rightEAR: 0.3,
                                  smileRatio: 2.0, browHeight: 0.03,
                                  mouthOpenRatio: 0.05, headRoll: 0.0,
                                  timestamp: t)
    }
    #expect(first.contains(where: { $0.type == .winkLeft }))
    // Immediately another wink (within cooldown)
    var second: [DetectedExpression] = []
    for i in 0..<5 {
        let t = 2.35 + Double(i) * (1.0/30.0)
        second += detector.update(leftEAR: 0.05, rightEAR: 0.3,
                                   smileRatio: 2.0, browHeight: 0.03,
                                   mouthOpenRatio: 0.05, headRoll: 0.0,
                                   timestamp: t)
    }
    #expect(!second.contains(where: { $0.type == .winkLeft }), "Should be in cooldown")
}

// MARK: - Helpers

private func feedNeutralFrames(detector: ExpressionDetector, count: Int) {
    for i in 0..<count {
        let t = Double(i) * (1.0/30.0)
        _ = detector.update(leftEAR: 0.3, rightEAR: 0.3,
                            smileRatio: 2.0, browHeight: 0.03,
                            mouthOpenRatio: 0.05, headRoll: 0.0,
                            timestamp: t)
    }
}

/// Make points approximating a rectangle (for lip shapes).
/// Returns 8 points around the perimeter.
private func makeRectPoints(cx: Double, cy: Double, width: Double, height: Double) -> [CGPoint] {
    let hw = width / 2, hh = height / 2
    return [
        CGPoint(x: cx + hw, y: cy),          // right
        CGPoint(x: cx + hw * 0.7, y: cy - hh * 0.7),
        CGPoint(x: cx, y: cy - hh),          // top
        CGPoint(x: cx - hw * 0.7, y: cy - hh * 0.7),
        CGPoint(x: cx - hw, y: cy),          // left
        CGPoint(x: cx - hw * 0.7, y: cy + hh * 0.7),
        CGPoint(x: cx, y: cy + hh),          // bottom
        CGPoint(x: cx + hw * 0.7, y: cy + hh * 0.7),
    ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | head -20`
Expected: Compilation error — `ExpressionDetector` not defined

- [ ] **Step 3: Implement ExpressionDetector**

```swift
// Sources/LucentCore/Tracking/ExpressionDetector.swift
import Foundation
import CoreGraphics

public final class ExpressionDetector: @unchecked Sendable {

    // MARK: - Configuration

    public var configs: [ExpressionType: ExpressionConfig] = ExpressionConfig.defaults
    public var winkClosedThreshold: Double = 0.15
    public var winkOpenThreshold: Double = 0.22
    public var baselineFrames: Int = 60

    // MARK: - Baseline State

    private var baselineSmileRatio: Double = 0
    private var baselineBrowHeight: Double = 0
    private var baselineMouthOpen: Double = 0
    private var baselineSamples: Int = 0
    private var baselineReady: Bool = false

    // Accumulation buffers for baseline
    private var smileSum: Double = 0
    private var browSum: Double = 0
    private var mouthSum: Double = 0

    // MARK: - Detection State

    private var activeExpressions: [ExpressionType: Double] = [:]  // type -> start time
    private var firedExpressions: [ExpressionType: Double] = [:]   // type -> last fire time

    public init() {}

    // MARK: - Main Update

    /// Process one frame of expression metrics. Returns any newly triggered expressions.
    public func update(
        leftEAR: Double, rightEAR: Double,
        smileRatio: Double, browHeight: Double,
        mouthOpenRatio: Double, headRoll: Double,
        timestamp: Double
    ) -> [DetectedExpression] {

        // Baseline calibration
        if !baselineReady {
            smileSum += smileRatio
            browSum += browHeight
            mouthSum += mouthOpenRatio
            baselineSamples += 1
            if baselineSamples >= baselineFrames {
                baselineSmileRatio = smileSum / Double(baselineSamples)
                baselineBrowHeight = browSum / Double(baselineSamples)
                baselineMouthOpen = mouthSum / Double(baselineSamples)
                baselineReady = true
            }
            return []
        }

        var detected: [DetectedExpression] = []

        // Check each expression
        let checks: [(ExpressionType, Bool, Double)] = [
            (.winkLeft, leftEAR < winkClosedThreshold && rightEAR > winkOpenThreshold,
             (winkOpenThreshold - leftEAR) / winkOpenThreshold),
            (.winkRight, rightEAR < winkClosedThreshold && leftEAR > winkOpenThreshold,
             (winkOpenThreshold - rightEAR) / winkOpenThreshold),
            (.smile, smileRatio > baselineSmileRatio * configs[.smile]!.thresholdMultiplier,
             smileRatio / (baselineSmileRatio * configs[.smile]!.thresholdMultiplier)),
            (.browRaise, browHeight > baselineBrowHeight * configs[.browRaise]!.thresholdMultiplier,
             browHeight / max(baselineBrowHeight * configs[.browRaise]!.thresholdMultiplier, 0.001)),
            (.mouthOpen, mouthOpenRatio > baselineMouthOpen * configs[.mouthOpen]!.thresholdMultiplier,
             mouthOpenRatio / max(baselineMouthOpen * configs[.mouthOpen]!.thresholdMultiplier, 0.001)),
        ]

        for (type, isActive, confidence) in checks {
            let config = configs[type]!

            if isActive {
                if activeExpressions[type] == nil {
                    activeExpressions[type] = timestamp
                }
                let heldFor = timestamp - activeExpressions[type]!
                if heldFor >= config.holdDuration {
                    // Check cooldown
                    if let lastFired = firedExpressions[type],
                       timestamp - lastFired < config.cooldown {
                        continue
                    }
                    // Fire!
                    detected.append(DetectedExpression(
                        type: type,
                        confidence: min(confidence, 1.0),
                        timestamp: timestamp
                    ))
                    firedExpressions[type] = timestamp
                    activeExpressions[type] = nil  // reset so it must re-trigger
                }
            } else {
                activeExpressions[type] = nil
            }
        }

        return detected
    }

    /// Reset baseline (e.g., after recalibration).
    public func resetBaseline() {
        baselineReady = false
        baselineSamples = 0
        smileSum = 0
        browSum = 0
        mouthSum = 0
        activeExpressions.removeAll()
        firedExpressions.removeAll()
    }

    // MARK: - Static Metric Computations

    /// Compute mouth open ratio from inner lip points.
    /// Returns height / width of the inner lip bounding box.
    public static func mouthOpenRatio(innerLipsPoints: [CGPoint]) -> Double {
        guard innerLipsPoints.count >= 4 else { return 0 }
        let xs = innerLipsPoints.map { Double($0.x) }
        let ys = innerLipsPoints.map { Double($0.y) }
        let width = (xs.max()! - xs.min()!)
        guard width > 0 else { return 0 }
        let height = (ys.max()! - ys.min()!)
        return height / width
    }

    /// Compute smile ratio from outer lip points.
    /// Returns width / height of outer lip bounding box (wide = smiling).
    public static func smileRatio(outerLipsPoints: [CGPoint]) -> Double {
        guard outerLipsPoints.count >= 4 else { return 0 }
        let xs = outerLipsPoints.map { Double($0.x) }
        let ys = outerLipsPoints.map { Double($0.y) }
        let height = (ys.max()! - ys.min()!)
        guard height > 0 else { return 0 }
        let width = (xs.max()! - xs.min()!)
        return width / height
    }

    /// Compute average brow height above the eye top.
    public static func browHeight(browPoints: [CGPoint], eyeTopY: CGFloat) -> Double {
        guard !browPoints.isEmpty else { return 0 }
        let avgBrowY = browPoints.map { Double($0.y) }.reduce(0, +) / Double(browPoints.count)
        // In our coordinate system, lower Y = higher on screen
        return Double(eyeTopY) - avgBrowY
    }

    /// Compute head roll angle in degrees from pupil positions.
    /// Positive = tilted right, negative = tilted left.
    public static func headRoll(leftPupil: CGPoint, rightPupil: CGPoint) -> Double {
        let dx = Double(rightPupil.x - leftPupil.x)
        let dy = Double(rightPupil.y - leftPupil.y)
        guard abs(dx) > 0.001 else { return 0 }
        return atan2(-dy, dx) * 180.0 / .pi
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/LucentCore/Tracking/ExpressionDetector.swift Tests/LucentCoreTests/ExpressionDetectorTests.swift
git commit -m "feat: add ExpressionDetector with geometric expression recognition"
```

---

## Task 4: HeadTiltProcessor (TDD)

**Files:**
- Create: `Sources/LucentCore/Control/HeadTiltProcessor.swift`
- Create: `Tests/LucentCoreTests/HeadTiltProcessorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/LucentCoreTests/HeadTiltProcessorTests.swift
import Testing
import CoreGraphics
@testable import LucentCore

@Test func noOffsetWhenLevel() {
    let processor = HeadTiltProcessor()
    let offset = processor.process(rollDegrees: 0.0)
    #expect(abs(offset.x) < 0.001)
    #expect(abs(offset.y) < 0.001)
}

@Test func noOffsetInDeadZone() {
    let processor = HeadTiltProcessor()
    let offset = processor.process(rollDegrees: 2.0)
    #expect(abs(offset.x) < 0.001)
}

@Test func offsetRightWhenTiltedRight() {
    let processor = HeadTiltProcessor()
    let offset = processor.process(rollDegrees: 10.0)
    #expect(offset.x > 3.0, "Should move cursor right")
}

@Test func offsetLeftWhenTiltedLeft() {
    let processor = HeadTiltProcessor()
    let offset = processor.process(rollDegrees: -10.0)
    #expect(offset.x < -3.0, "Should move cursor left")
}

@Test func largerTiltProducesLargerOffset() {
    let processor = HeadTiltProcessor()
    let small = processor.process(rollDegrees: 10.0)
    let large = processor.process(rollDegrees: 20.0)
    #expect(large.x > small.x)
}

@Test func disabledReturnsZero() {
    let processor = HeadTiltProcessor()
    processor.isEnabled = false
    let offset = processor.process(rollDegrees: 15.0)
    #expect(abs(offset.x) < 0.001)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | head -20`
Expected: Compilation error

- [ ] **Step 3: Implement HeadTiltProcessor**

```swift
// Sources/LucentCore/Control/HeadTiltProcessor.swift
import Foundation

public final class HeadTiltProcessor: @unchecked Sendable {

    public var deadZoneDegrees: Double = 3.0
    public var pixelsPerDegree: Double = 0.7  // 10° beyond dead zone ≈ 5px
    public var isEnabled: Bool = true

    public init() {}

    /// Process head roll angle and return cursor offset in pixels.
    /// Positive roll = tilted right = positive x offset.
    public func process(rollDegrees: Double) -> GazePoint {
        guard isEnabled else { return .zero }

        let absRoll = abs(rollDegrees)
        guard absRoll > deadZoneDegrees else { return .zero }

        let effectiveRoll = absRoll - deadZoneDegrees
        let magnitude = effectiveRoll * pixelsPerDegree
        let direction = rollDegrees > 0 ? 1.0 : -1.0

        return GazePoint(x: magnitude * direction, y: 0)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/LucentCore/Control/HeadTiltProcessor.swift Tests/LucentCoreTests/HeadTiltProcessorTests.swift
git commit -m "feat: add HeadTiltProcessor with dead zone and linear scaling"
```

---

## Task 5: InputModeManager (TDD)

**Files:**
- Create: `Sources/LucentCore/Control/InputModeManager.swift`
- Create: `Tests/LucentCoreTests/InputModeManagerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/LucentCoreTests/InputModeManagerTests.swift
import Testing
@testable import LucentCore

@Test func startsInNormalMode() {
    let manager = InputModeManager()
    #expect(manager.currentMode == .normal)
}

@Test func mouthOpenSwitchesToScroll() {
    let manager = InputModeManager()
    let events = manager.process(expressions: [
        DetectedExpression(type: .mouthOpen, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .scroll)
    #expect(events.contains(.modeChanged(from: .normal, to: .scroll)))
}

@Test func mouthCloseExitsScroll() {
    let manager = InputModeManager()
    _ = manager.process(expressions: [
        DetectedExpression(type: .mouthOpen, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .scroll)
    // No mouth open expression = mouth closed → exit scroll
    let events = manager.process(expressions: [])
    #expect(manager.currentMode == .normal)
    #expect(events.contains(.modeChanged(from: .scroll, to: .normal)))
}

@Test func smileTogglesDictation() {
    let manager = InputModeManager()
    let on = manager.process(expressions: [
        DetectedExpression(type: .smile, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .dictation)
    #expect(on.contains(.modeChanged(from: .normal, to: .dictation)))
    // Smile again toggles off
    let off = manager.process(expressions: [
        DetectedExpression(type: .smile, confidence: 0.8, timestamp: 2.0)
    ])
    #expect(manager.currentMode == .normal)
    #expect(off.contains(.modeChanged(from: .dictation, to: .normal)))
}

@Test func browRaiseTogglesCommandPalette() {
    let manager = InputModeManager()
    let on = manager.process(expressions: [
        DetectedExpression(type: .browRaise, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .commandPalette)
    let off = manager.process(expressions: [
        DetectedExpression(type: .browRaise, confidence: 0.8, timestamp: 2.0)
    ])
    #expect(manager.currentMode == .normal)
}

@Test func winkLeftTriggersAction() {
    let manager = InputModeManager()
    let events = manager.process(expressions: [
        DetectedExpression(type: .winkLeft, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(events.contains(.actionTriggered(.winkLeft)))
    #expect(manager.currentMode == .normal, "Winks don't change mode")
}

@Test func winkRightTriggersAction() {
    let manager = InputModeManager()
    let events = manager.process(expressions: [
        DetectedExpression(type: .winkRight, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(events.contains(.actionTriggered(.winkRight)))
}

@Test func faceLostReturnsToNormal() {
    let manager = InputModeManager()
    _ = manager.process(expressions: [
        DetectedExpression(type: .mouthOpen, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .scroll)
    let events = manager.handleFaceLost()
    #expect(manager.currentMode == .normal)
    #expect(events.contains(.modeChanged(from: .scroll, to: .normal)))
}

@Test func faceLostFromNormalNoEvent() {
    let manager = InputModeManager()
    let events = manager.handleFaceLost()
    #expect(events.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | head -20`
Expected: Compilation error

- [ ] **Step 3: Implement InputModeManager**

```swift
// Sources/LucentCore/Control/InputModeManager.swift
import Foundation

public final class InputModeManager: @unchecked Sendable {

    public private(set) var currentMode: InputMode = .normal

    // Track whether scroll mode's hold-to-activate is still held
    private var scrollHeld = false

    public init() {}

    /// Process detected expressions and return mode/action events.
    public func process(expressions: [DetectedExpression]) -> [ModeEvent] {
        var events: [ModeEvent] = []
        let types = Set(expressions.map(\.type))

        // Scroll mode: mouth open = hold to activate, close = deactivate
        if currentMode == .scroll {
            if !types.contains(.mouthOpen) {
                let event = ModeEvent.modeChanged(from: .scroll, to: .normal)
                currentMode = .normal
                scrollHeld = false
                events.append(event)
            }
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
                    // Toggle off
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
                // Winks are actions, not mode switches — work in any mode
                events.append(.actionTriggered(expression.type))
            }
        }

        return events
    }

    /// Handle face lost — reset to normal mode.
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

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/LucentCore/Control/InputModeManager.swift Tests/LucentCoreTests/InputModeManagerTests.swift
git commit -m "feat: add InputModeManager state machine for mode transitions"
```

---

## Task 6: BlinkDetector isEnabled + InputController scroll/pressKey

**Files:**
- Modify: `Sources/LucentCore/Tracking/BlinkDetector.swift`
- Modify: `Sources/LucentCore/Control/InputController.swift`

- [ ] **Step 1: Add isEnabled to BlinkDetector**

Add at the top of BlinkDetector's properties (after the configuration section):

```swift
public var isEnabled: Bool = true
```

Add as the first line of `update(ear:timestamp:)`:

```swift
guard isEnabled else { return [] }
```

- [ ] **Step 2: Add scroll and pressKey to InputController**

Add these methods to InputController:

```swift
/// Post scroll wheel events.
public func scroll(deltaY: Int32, deltaX: Int32 = 0) {
    if let event = CGEvent(scrollWheelEvent2Source: eventSource,
                           units: .pixel,
                           wheelCount: 2,
                           wheel1: deltaY,
                           wheel2: deltaX) {
        event.post(tap: .cghidEventTap)
    }
}

/// Simulate a key press with optional modifiers.
/// keyCode: virtual key code (e.g., 0x31 for Space, 0x35 for Escape)
/// modifiers: CGEventFlags (e.g., .maskCommand)
public func pressKey(keyCode: UInt16, modifiers: CGEventFlags = []) {
    if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
       let up = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) {
        down.flags = modifiers
        up.flags = modifiers
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

/// Simulate pressing Fn twice (for macOS dictation).
public func triggerDictation() {
    // Fn key = keyCode 0x3F
    pressKey(keyCode: 0x3F)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
        pressKey(keyCode: 0x3F)
    }
}

/// Simulate Cmd+Space (for Spotlight).
public func triggerSpotlight() {
    pressKey(keyCode: 0x31, modifiers: .maskCommand)  // 0x31 = Space
}
```

- [ ] **Step 3: Verify build and tests**

Run: `swift test`
Expected: All tests pass (existing BlinkDetector tests still work since isEnabled defaults to true)

- [ ] **Step 4: Commit**

```bash
git add Sources/LucentCore/Tracking/BlinkDetector.swift Sources/LucentCore/Control/InputController.swift
git commit -m "feat: add BlinkDetector.isEnabled, InputController.scroll/pressKey/triggerDictation/triggerSpotlight"
```

---

## Task 7: Update FrameProcessor

**Files:**
- Modify: `Sources/LucentCore/Camera/FrameProcessor.swift`

- [ ] **Step 1: Expand FrameResult and add expression detection**

Replace the entire file:

```swift
// Sources/LucentCore/Camera/FrameProcessor.swift
import Foundation
import CoreGraphics
import CoreImage

public final class FrameProcessor: @unchecked Sendable {

    public struct FrameResult: Sendable {
        public let rawGaze: GazePoint
        public let leftEAR: Double
        public let rightEAR: Double
        public let faceDetected: Bool
        public let confidence: Float
        public let timestamp: Double
        public let expressions: [DetectedExpression]
        public let headRoll: Double
        public let smileRatio: Double
        public let browHeight: Double
        public let mouthOpenRatio: Double
    }

    private let landmarkDetector = FaceLandmarkDetector()
    private let gazeEstimator: any GazeEstimating
    private let expressionDetector = ExpressionDetector()

    public init(gazeEstimator: any GazeEstimating) {
        self.gazeEstimator = gazeEstimator
    }

    public func process(pixelBuffer: CVPixelBuffer, timestamp: Double) -> FrameResult? {
        guard let face = landmarkDetector.detect(in: pixelBuffer) else { return nil }

        let gaze = gazeEstimator.estimate(
            faceBounds: face.faceBounds,
            leftPupil: face.leftPupil,
            rightPupil: face.rightPupil
        )

        let leftEAR = BlinkDetector.computeEAR(eyePoints: face.leftEyePoints)
        let rightEAR = BlinkDetector.computeEAR(eyePoints: face.rightEyePoints)

        // Expression metrics
        let smile = ExpressionDetector.smileRatio(outerLipsPoints: face.outerLipsPoints)
        let mouthOpen = ExpressionDetector.mouthOpenRatio(innerLipsPoints: face.innerLipsPoints)

        // Brow height: average of left and right brow relative to eye top
        let leftEyeTopY = face.leftEyePoints.map(\.y).min() ?? 0
        let rightEyeTopY = face.rightEyePoints.map(\.y).min() ?? 0
        let leftBrow = ExpressionDetector.browHeight(browPoints: face.leftBrowPoints, eyeTopY: leftEyeTopY)
        let rightBrow = ExpressionDetector.browHeight(browPoints: face.rightBrowPoints, eyeTopY: rightEyeTopY)
        let avgBrowHeight = (leftBrow + rightBrow) / 2.0

        let roll = ExpressionDetector.headRoll(leftPupil: face.leftPupil, rightPupil: face.rightPupil)

        let expressions = expressionDetector.update(
            leftEAR: leftEAR, rightEAR: rightEAR,
            smileRatio: smile, browHeight: avgBrowHeight,
            mouthOpenRatio: mouthOpen, headRoll: roll,
            timestamp: timestamp
        )

        return FrameResult(
            rawGaze: gaze,
            leftEAR: leftEAR,
            rightEAR: rightEAR,
            faceDetected: true,
            confidence: face.confidence,
            timestamp: timestamp,
            expressions: expressions,
            headRoll: roll,
            smileRatio: smile,
            browHeight: avgBrowHeight,
            mouthOpenRatio: mouthOpen
        )
    }
}
```

- [ ] **Step 2: Verify build and tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add Sources/LucentCore/Camera/FrameProcessor.swift
git commit -m "feat: expand FrameProcessor with expression detection and head roll"
```

---

## Task 8: TrackingPipeline Integration

**Files:**
- Modify: `App/TrackingPipeline.swift`

- [ ] **Step 1: Replace TrackingPipeline with mode-aware version**

Replace the entire file:

```swift
// App/TrackingPipeline.swift
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

    private let cameraManager = CameraManager()
    private let frameProcessor: FrameProcessor
    private let blinkDetector = BlinkDetector()
    private let cursorSmoother: CursorSmoother
    private let inputController = InputController()
    private let modeManager = InputModeManager()
    private let headTiltProcessor = HeadTiltProcessor()
    private var calibrationProfile: CalibrationProfile?

    private var faceLostTime: Double?
    private let faceLostTimeout: Double = 0.5
    private var lowConfidenceCount = 0

    public var cameraDeviceID: String {
        cameraManager.currentDeviceID ?? "unknown"
    }

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
    }

    public func toggle() throws {
        if isEnabled { stop() } else { try start() }
    }

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

        if result.confidence < 0.5 {
            lowConfidenceCount += 1
            if lowConfidenceCount > 30 { trackingState = .paused(reason: .poorLighting) }
        } else { lowConfidenceCount = 0 }

        guard let profile = calibrationProfile else {
            trackingState = .detecting
            return
        }
        trackingState = .tracking

        // Process expressions through mode manager
        let modeEvents = modeManager.process(expressions: result.expressions)
        currentMode = modeManager.currentMode

        // Handle mode events
        for event in modeEvents {
            handleModeEvent(event, at: result.timestamp)
        }

        // Configure blink detector based on mode
        blinkDetector.isEnabled = (currentMode == .normal || currentMode == .commandPalette)

        // Head tilt only in normal mode
        headTiltProcessor.isEnabled = (currentMode == .normal)

        // Mode-specific behavior
        switch currentMode {
        case .normal, .commandPalette:
            handleNormalTracking(result, profile: profile)
        case .scroll:
            handleScrollMode(result, profile: profile)
        case .dictation:
            // Cursor frozen, just process wink clicks
            handleWinkClicks(result)
        }
    }

    private func handleNormalTracking(_ result: FrameProcessor.FrameResult, profile: CalibrationProfile) {
        let screenPoint = profile.mapToScreen(result.rawGaze)
        let smoothed = cursorSmoother.smooth(screenPoint)

        // Apply head tilt offset
        let tiltOffset = headTiltProcessor.process(rollDegrees: result.headRoll)
        let final = GazePoint(x: smoothed.x + tiltOffset.x, y: smoothed.y + tiltOffset.y)

        currentCursorPosition = final
        inputController.moveCursor(to: final)

        // Blink clicks
        let avgEAR = (result.leftEAR + result.rightEAR) / 2.0
        let clickEvents = blinkDetector.update(ear: avgEAR, timestamp: result.timestamp)
        for event in clickEvents {
            switch event {
            case .leftClick: inputController.leftClick(at: final)
            case .rightClick: inputController.rightClick(at: final)
            case .doubleClick: inputController.doubleClick(at: final)
            }
        }

        // Wink clicks (in addition to blinks)
        handleWinkClicks(result)
    }

    private func handleScrollMode(_ result: FrameProcessor.FrameResult, profile: CalibrationProfile) {
        let screenPoint = profile.mapToScreen(result.rawGaze)
        let screenHeight = profile.screenHeight
        let screenWidth = profile.screenWidth

        // Vertical scroll: distance from center determines speed
        let verticalCenter = screenHeight / 2.0
        let verticalDeadZone = screenHeight * 0.1
        let verticalOffset = screenPoint.y - verticalCenter

        var scrollY: Int32 = 0
        if abs(verticalOffset) > verticalDeadZone {
            let speed = (abs(verticalOffset) - verticalDeadZone) / (screenHeight / 2.0)
            scrollY = Int32(speed * -10.0 * (verticalOffset > 0 ? 1 : -1))
        }

        // Horizontal scroll
        let horizontalCenter = screenWidth / 2.0
        let horizontalDeadZone = screenWidth * 0.1
        let horizontalOffset = screenPoint.x - horizontalCenter

        var scrollX: Int32 = 0
        if abs(horizontalOffset) > horizontalDeadZone {
            let speed = (abs(horizontalOffset) - horizontalDeadZone) / (screenWidth / 2.0)
            scrollX = Int32(speed * 10.0 * (horizontalOffset > 0 ? 1 : -1))
        }

        if scrollY != 0 || scrollX != 0 {
            inputController.scroll(deltaY: scrollY, deltaX: scrollX)
        }

        // Wink clicks still work in scroll mode
        handleWinkClicks(result)
    }

    private func handleWinkClicks(_ result: FrameProcessor.FrameResult) {
        for expression in result.expressions {
            switch expression.type {
            case .winkLeft:
                inputController.rightClick(at: currentCursorPosition)
            case .winkRight:
                inputController.doubleClick(at: currentCursorPosition)
            default:
                break
            }
        }
    }

    private func handleModeEvent(_ event: ModeEvent, at timestamp: Double) {
        switch event {
        case .modeChanged(_, let to):
            switch to {
            case .dictation:
                inputController.triggerDictation()
            case .commandPalette:
                inputController.triggerSpotlight()
            case .normal:
                // If exiting dictation, dismiss it
                break
            case .scroll:
                break
            }
        case .actionTriggered:
            break  // handled in handleWinkClicks
        }
    }

    private func handleFaceLost(at time: Double) {
        if faceLostTime == nil { faceLostTime = time }
        if let lost = faceLostTime, time - lost > faceLostTimeout {
            trackingState = .paused(reason: .faceLost)
            let events = modeManager.handleFaceLost()
            if !events.isEmpty { currentMode = .normal }
        }
    }
}
```

- [ ] **Step 2: Regenerate Xcode project and verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 3: Run swift tests to verify core still passes**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add App/TrackingPipeline.swift
git commit -m "feat: integrate expression detection, mode switching, head tilt into pipeline"
```

---

## Task 9: HUD Panel + Views

**Files:**
- Create: `App/UI/HUDPanel.swift`
- Create: `App/UI/HUDMinimalView.swift`
- Create: `App/UI/HUDExpandedView.swift`
- Create: `App/UI/HUDToastView.swift`

- [ ] **Step 1: Create HUDPanel (NSPanel wrapper)**

```swift
// App/UI/HUDPanel.swift
import SwiftUI
import AppKit

final class HUDPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
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

    func resize(to size: NSSize) {
        let origin = frame.origin
        setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
    }
}
```

- [ ] **Step 2: Create HUDMinimalView**

```swift
// App/UI/HUDMinimalView.swift
import SwiftUI
import LucentCore

struct HUDMinimalView: View {
    let mode: InputMode
    let confidence: Float
    let activeExpression: ExpressionType?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: modeIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)

            Circle()
                .fill(confidenceColor)
                .frame(width: 6, height: 6)

            if let expr = activeExpression {
                Image(systemName: expressionIcon(expr))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var modeIcon: String {
        switch mode {
        case .normal: return "eye"
        case .scroll: return "scroll"
        case .dictation: return "mic"
        case .commandPalette: return "magnifyingglass"
        }
    }

    private var confidenceColor: Color {
        if confidence > 0.7 { return .green }
        if confidence > 0.4 { return .yellow }
        return .red
    }

    private func expressionIcon(_ type: ExpressionType) -> String {
        switch type {
        case .winkLeft, .winkRight: return "eye.slash"
        case .smile: return "face.smiling"
        case .browRaise: return "eyebrow"
        case .mouthOpen: return "mouth"
        }
    }
}
```

- [ ] **Step 3: Create HUDExpandedView**

```swift
// App/UI/HUDExpandedView.swift
import SwiftUI
import LucentCore

struct HUDExpandedView: View {
    let mode: InputMode
    let confidence: Float
    let expressions: [DetectedExpression]
    let cursorPosition: GazePoint

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Mode header
            HStack {
                Image(systemName: modeIcon)
                    .font(.system(size: 16, weight: .semibold))
                Text(modeName)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Circle()
                    .fill(confidenceColor)
                    .frame(width: 8, height: 8)
                Text("\(Int(confidence * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider().opacity(0.3)

            // Active expressions
            if expressions.isEmpty {
                Text("No expressions")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ForEach(expressions, id: \.type) { expr in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 5, height: 5)
                        Text(expr.type.rawValue)
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text("\(Int(expr.confidence * 100))%")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider().opacity(0.3)

            // Cursor position
            HStack {
                Text("Cursor")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("(\(Int(cursorPosition.x)), \(Int(cursorPosition.y)))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var modeIcon: String {
        switch mode {
        case .normal: return "eye"
        case .scroll: return "scroll"
        case .dictation: return "mic"
        case .commandPalette: return "magnifyingglass"
        }
    }

    private var modeName: String {
        switch mode {
        case .normal: return "Normal"
        case .scroll: return "Scroll"
        case .dictation: return "Dictation"
        case .commandPalette: return "Command Palette"
        }
    }

    private var confidenceColor: Color {
        if confidence > 0.7 { return .green }
        if confidence > 0.4 { return .yellow }
        return .red
    }
}
```

- [ ] **Step 4: Create HUDToastView**

```swift
// App/UI/HUDToastView.swift
import SwiftUI

struct HUDToastView: View {
    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.75))
        )
        .foregroundColor(.white)
    }
}
```

- [ ] **Step 5: Verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add App/UI/HUDPanel.swift App/UI/HUDMinimalView.swift App/UI/HUDExpandedView.swift App/UI/HUDToastView.swift
git commit -m "feat: add HUD panel with minimal pill, expanded dashboard, and toast views"
```

---

## Task 10: AppState + MenuBarView Updates

**Files:**
- Modify: `App/AppState.swift`
- Modify: `App/UI/MenuBarView.swift`

- [ ] **Step 1: Update AppState with HUD state and Cmd+Shift+H hotkey**

Replace `App/AppState.swift`:

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
    @Published public var showHUD: Bool
    @Published public var hudExpanded: Bool

    private var hotkeyRef: EventHotKeyRef?
    private var hudHotkeyRef: EventHotKeyRef?

    public init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.showHUD = UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true
        self.hudExpanded = UserDefaults.standard.bool(forKey: "hudExpanded")
        registerGlobalHotkeys()
    }

    public func toggleTracking() {
        do { try pipeline.toggle() }
        catch { print("Failed to toggle tracking: \(error)") }
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    public func toggleHUDExpanded() {
        hudExpanded.toggle()
        UserDefaults.standard.set(hudExpanded, forKey: "hudExpanded")
    }

    public var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch { print("Failed to set launch at login: \(error)") }
        }
    }

    private func registerGlobalHotkeys() {
        // Cmd+Shift+L — toggle tracking
        var trackingHotKeyID = EventHotKeyID()
        trackingHotKeyID.signature = OSType(0x4C554345)  // "LUCE"
        trackingHotKeyID.id = 1
        var ref1: EventHotKeyRef?
        RegisterEventHotKey(0x25, UInt32(cmdKey | shiftKey), trackingHotKeyID, GetApplicationEventTarget(), 0, &ref1)
        hotkeyRef = ref1

        // Cmd+Shift+H — toggle HUD expanded
        var hudHotKeyID = EventHotKeyID()
        hudHotKeyID.signature = OSType(0x4C554345)
        hudHotKeyID.id = 2
        var ref2: EventHotKeyRef?
        RegisterEventHotKey(0x04, UInt32(cmdKey | shiftKey), hudHotKeyID, GetApplicationEventTarget(), 0, &ref2)
        hudHotkeyRef = ref2

        // Event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                            EventParamType(typeEventHotKeyID), nil,
                            MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            switch hotKeyID.id {
            case 1: NotificationCenter.default.post(name: .toggleTracking, object: nil)
            case 2: NotificationCenter.default.post(name: .toggleHUD, object: nil)
            default: break
            }
            return noErr
        }, 1, &eventType, nil, nil)

        NotificationCenter.default.addObserver(forName: .toggleTracking, object: nil, queue: .main) { [weak self] _ in
            self?.toggleTracking()
        }
        NotificationCenter.default.addObserver(forName: .toggleHUD, object: nil, queue: .main) { [weak self] _ in
            self?.toggleHUDExpanded()
        }
    }
}

extension Notification.Name {
    static let toggleTracking = Notification.Name("com.lucent.toggleTracking")
    static let toggleHUD = Notification.Name("com.lucent.toggleHUD")
}
```

- [ ] **Step 2: Update MenuBarView with mode display and HUD toggle**

Replace `App/UI/MenuBarView.swift`:

```swift
// App/UI/MenuBarView.swift
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
                    Image(systemName: modeIcon)
                        .font(.system(size: 11))
                    Text(modeName)
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }

            Divider()

            Toggle("Eye Tracking", isOn: Binding(
                get: { appState.pipeline.isEnabled },
                set: { _ in appState.toggleTracking() }
            ))

            Toggle("Show HUD", isOn: Binding(
                get: { appState.showHUD },
                set: { appState.showHUD = $0; UserDefaults.standard.set($0, forKey: "showHUD") }
            ))

            Button("Quick Recalibrate") { appState.showCalibration = true }
                .disabled(!appState.pipeline.isEnabled)

            Divider()

            Button("Settings...") {
                appState.showSettings = true
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit Lucent") { NSApplication.shared.terminate(nil) }
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

    private var modeIcon: String {
        switch appState.pipeline.currentMode {
        case .normal: return "eye"
        case .scroll: return "scroll"
        case .dictation: return "mic"
        case .commandPalette: return "magnifyingglass"
        }
    }

    private var modeName: String {
        switch appState.pipeline.currentMode {
        case .normal: return "Normal"
        case .scroll: return "Scroll Mode"
        case .dictation: return "Dictation"
        case .commandPalette: return "Command Palette"
        }
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug -quiet`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add App/AppState.swift App/UI/MenuBarView.swift
git commit -m "feat: add HUD toggle, Cmd+Shift+H hotkey, mode display in menu bar"
```

---

## Task 11: Final Integration

- [ ] **Step 1: Run all unit tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 2: Build the full app**

Run: `xcodegen generate && xcodebuild build -project Lucent.xcodeproj -scheme Lucent -configuration Debug`
Expected: Build succeeds

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "feat: complete Phase 2 — face expressions + HUD overlay"
```

- [ ] **Step 4: Push**

```bash
git push origin main
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | InputMode models | Build verification |
| 2 | FaceData expansion | Existing tests pass |
| 3 | ExpressionDetector | 14 tests (metrics, detection, cooldown) |
| 4 | HeadTiltProcessor | 6 tests (dead zone, scaling, disable) |
| 5 | InputModeManager | 9 tests (transitions, face lost, actions) |
| 6 | BlinkDetector isEnabled + InputController scroll/pressKey | Existing tests pass |
| 7 | FrameProcessor update | Existing tests pass |
| 8 | TrackingPipeline integration | Build verification |
| 9 | HUD Panel + Views | Build verification |
| 10 | AppState + MenuBarView updates | Build verification |
| 11 | Final integration | Full test suite + build |

**Total: 11 tasks, ~29 new unit tests, 11 commits**
