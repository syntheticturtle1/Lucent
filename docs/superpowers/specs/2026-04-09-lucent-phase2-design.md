# Lucent Phase 2: Face Expressions + HUD Overlay

**Date:** 2026-04-09
**Status:** Draft
**Scope:** Phase 2 of 5 — expression-based actions, input mode switching, floating HUD
**Depends on:** Phase 1 (eye cursor + blink click)

## Overview

Phase 2 adds face expression recognition and a floating HUD overlay to Lucent. Users gain new input actions (wink-to-right-click, smile for dictation, brow raise for Spotlight, mouth open for scroll mode) and a head tilt fine-cursor mechanism. A translucent always-on-top HUD provides real-time feedback on tracking state, active mode, and detected expressions.

**Goal:** A user can switch between input modes, trigger actions via facial expressions, and see real-time tracking feedback — all without touching the keyboard or mouse.

**Non-goals for Phase 2:**
- Hand tracking and gestures (Phase 3)
- Air typing / virtual keyboard (Phase 4)
- Full expression mapping editor UI (Phase 5 — Phase 2 ships with sensible defaults and a data model ready for UI)

## Approach

Geometric analysis of existing Vision landmarks. No new ML models. The 76 landmarks already extracted in Phase 1 include eye contours, pupils, outer/inner lips, eyebrows, and face contour. Phase 2 extracts the additional landmark regions (mouth, brows) and computes geometric ratios to classify expressions. This adds <1ms to frame processing.

## Expression Detection

### ExpressionDetector

A new component in `LucentCore/Tracking/` that takes `FaceData` and produces a list of currently active expressions.

**Expressions and geometric signatures:**

| Expression | Metric | Computation |
|---|---|---|
| Wink (left) | EAR asymmetry | Left EAR < 0.15 while right EAR > 0.22 |
| Wink (right) | EAR asymmetry | Right EAR < 0.15 while left EAR > 0.22 |
| Smile | Mouth width/height + corner upturn | Outer lip width / outer lip height > resting × 1.4, lip corners higher than lip center |
| Brow raise | Brow-to-eye distance | Average distance from brow points to upper eye contour > resting × 1.3 |
| Mouth open | Inner lip height ratio | Inner lip height / face height > resting × 2.0 |
| Head tilt | Eye center roll angle | Angle between left and right eye centers vs horizontal |

### Detection Parameters

Each expression has:
- **Detection threshold:** configurable ratio relative to resting baseline
- **Hold duration:** how long the expression must be sustained to trigger (prevents false positives)
  - Winks: 150ms (fast action)
  - Smile: 500ms (mode toggle — needs to be deliberate)
  - Brow raise: 300ms
  - Mouth open: 300ms
- **Cooldown:** minimum time after triggering before re-detection
  - Winks: 300ms
  - Mode toggles: 500ms
- **Resting baseline:** calibrated from the user's neutral face. Collected over the first 2 seconds of tracking (30fps × 2s = 60 frames). Stores average metric values for each expression. Recalibrates when the user runs eye calibration.

### FaceData Expansion

`FaceData` (in `FaceLandmarkDetector.swift`) adds these fields:
- `outerLipsPoints: [CGPoint]` — from `VNFaceLandmarks2D.outerLips`
- `innerLipsPoints: [CGPoint]` — from `VNFaceLandmarks2D.innerLips`
- `leftBrowPoints: [CGPoint]` — from `VNFaceLandmarks2D.leftEyebrow`
- `rightBrowPoints: [CGPoint]` — from `VNFaceLandmarks2D.rightEyebrow`

These are extracted using the same `convertPoints()` helper that already handles eye contours.

### DetectedExpression Type

```
public enum ExpressionType: String, Codable, Sendable {
    case winkLeft, winkRight, smile, browRaise, mouthOpen
}

public struct DetectedExpression: Sendable {
    public let type: ExpressionType
    public let confidence: Double  // 0..1, how far past threshold
    public let timestamp: Double
}
```

## Input Modes

### InputMode Enum

```
public enum InputMode: String, Codable, Sendable {
    case normal      // Eye moves cursor, blink/wink clicks
    case scroll      // Eye position controls scroll speed/direction
    case dictation   // Cursor paused, macOS dictation active
    case commandPalette  // Spotlight open, eye tracking continues
}
```

### Mode Behavior

| Mode | Eye tracking | Blink click | Wink click | Activated by | Deactivated by |
|---|---|---|---|---|---|
| Normal | Moves cursor | Enabled | Enabled | Default / other mode exits | Entering another mode |
| Scroll | Vertical = scroll speed, horizontal = h-scroll | Disabled | Enabled (to click while scrolling) | Mouth open hold 300ms | Close mouth (immediate, no delay) |
| Dictation | Cursor paused at current position | Disabled | Enabled | Smile hold 500ms | Smile again (toggle) |
| Command Palette | Moves cursor (for Spotlight navigation) | Enabled | Enabled | Brow raise hold 300ms | Spotlight closes or brow raise again |

### InputModeManager

State machine managing transitions between modes. Located in `LucentCore/Control/`.

Responsibilities:
- Tracks current mode
- Receives expression events from ExpressionDetector
- Validates transitions (only one mode at a time)
- Emits mode change events (for HUD toasts)
- On face lost → returns to Normal mode
- Publishes current mode for pipeline and HUD

### Scroll Mode Details

When scroll mode is active:
- Gaze vertical position relative to screen center determines scroll direction and speed
  - Above center: scroll up, speed proportional to distance from center
  - Below center: scroll down
  - Near center (dead zone ±10% of screen height): no scroll
- Gaze horizontal position works the same for horizontal scroll
- Scroll events posted via `CGEvent` scroll wheel events
- `InputController` gets a new `scroll(deltaY:deltaX:)` method

### Dictation Mode Details

When dictation mode is active:
- Cursor freezes at current position
- App simulates pressing `fn` twice via CGEvent to trigger macOS dictation
- Tracking continues in background so face-lost detection still works
- Smile again toggles dictation off (simulates `fn` twice again to dismiss, or Escape)

### Command Palette Mode Details

When command palette mode is active:
- App simulates `Cmd+Space` via CGEvent to open Spotlight
- Eye tracking continues for navigating Spotlight results
- Blink-to-click works for selecting results
- Mode exits when Spotlight closes (detected via `NSWorkspace.shared.frontmostApplication` — if frontmost app changes away from Spotlight after 500ms, assume dismissed) or on another brow raise

## Head Tilt Fine Cursor

`HeadTiltProcessor` in `LucentCore/Control/`.

- **Input:** Roll angle computed from angle between left and right eye center points
- **Dead zone:** ±3° ignored (natural resting variation)
- **Movement mapping:** Beyond dead zone, linear scaling — 10° tilt ≈ 5px/frame, 20° ≈ 15px/frame
- **Direction:** Tilt left → cursor moves left. Tilt right → cursor moves right.
- **Application:** Offset is added to the smoothed gaze position in `TrackingPipeline.handleFrame()` before posting to `InputController`
- **Active only in Normal mode** — disabled during Scroll, Dictation, Command Palette

## HUD Overlay

### Architecture

An `NSPanel` subclass (`HUDPanel`) with:
- `.nonactivatingPanel` style mask — doesn't steal focus
- `.floating` window level — renders above all app windows
- `ignoresMouseEvents = true` — fully click-through
- SwiftUI content hosted via `NSHostingView`
- Position anchored to a screen corner (default: bottom-center), stored in UserDefaults

### Three Layers

**Layer 1: Minimal Pill (default)**
- ~120×32px semi-transparent rounded rectangle
- Content: mode icon (SF Symbols: `eye` / `scroll` / `mic` / `magnifyingglass`), face confidence dot (green/yellow/red circle), active expression icon when one fires
- Fades to 20% opacity after 3 seconds of no state changes. Returns to full opacity on any change.

**Layer 2: Expanded Dashboard (toggle via Cmd+Shift+H)**
- ~280×180px panel replacing the pill
- Content: current mode name and icon, face landmark wireframe (dots rendered from live landmark positions), list of detected expressions with names, gaze position crosshair indicator, cursor smoothing level bar
- Same transparency and click-through behavior

**Layer 3: Contextual Toasts (always active)**
- Small text pills that slide in above the HUD, auto-dismiss after 2 seconds
- Triggered by: mode switches ("Scroll Mode"), expression triggers ("Smile → Dictation"), tracking errors ("Face lost — cursor frozen"), recalibration
- Queue-based: if multiple toasts fire rapidly, they stack vertically with newest on top

### HUD Toggle

- `Cmd+Shift+H` toggles between minimal and expanded
- Menu bar popover gets a "Show HUD" toggle
- HUD visibility persisted in UserDefaults

## Changes to Phase 1 Files

| File | Change |
|---|---|
| `FaceLandmarkDetector.swift` | Add extraction of `outerLips`, `innerLips`, `leftEyebrow`, `rightEyebrow` landmark regions to `FaceData` |
| `FaceData` (in above) | Add `outerLipsPoints`, `innerLipsPoints`, `leftBrowPoints`, `rightBrowPoints` fields |
| `FrameProcessor.swift` | Add `ExpressionDetector` usage; expand `FrameResult` with `expressions: [DetectedExpression]`, `headRoll: Double` |
| `BlinkDetector.swift` | Add `isEnabled: Bool` property (default true). When false, `update()` returns empty array |
| `InputController.swift` | Add `scroll(deltaY:deltaX:)` method, `pressKey(_:modifiers:)` method for dictation/Spotlight triggers |
| `TrackingPipeline.swift` | Integrate `InputModeManager`, `HeadTiltProcessor`, mode-specific behavior in `handleFrame()` |
| `AppState.swift` | Add HUD visibility state, register `Cmd+Shift+H` hotkey |
| `MenuBarView.swift` | Add "Show HUD" toggle, display current mode |

## New Files

| File | Location | Purpose |
|---|---|---|
| `ExpressionDetector.swift` | `Sources/LucentCore/Tracking/` | Geometric expression detection from landmarks |
| `InputMode.swift` | `Sources/LucentCore/Models/` | `InputMode` enum, `ExpressionType` enum, `DetectedExpression` struct, `ExpressionConfig` model |
| `InputModeManager.swift` | `Sources/LucentCore/Control/` | Mode state machine, expression-to-action dispatch |
| `HeadTiltProcessor.swift` | `Sources/LucentCore/Control/` | Roll angle → cursor pixel offset |
| `HUDPanel.swift` | `App/UI/` | NSPanel subclass for floating overlay |
| `HUDMinimalView.swift` | `App/UI/` | Minimal pill SwiftUI view |
| `HUDExpandedView.swift` | `App/UI/` | Dashboard SwiftUI view |
| `HUDToastView.swift` | `App/UI/` | Toast notification SwiftUI view |

## Testing Strategy

- **Unit tests:** ExpressionDetector (geometric ratios with synthetic landmark arrays), InputModeManager (state machine transitions, expression dispatch, face-lost recovery), HeadTiltProcessor (dead zone, linear scaling, mode gating)
- **Integration tests:** Expression detection → mode switch → correct pipeline behavior with synthetic frame data
- **Manual testing:** HUD appearance/position/transparency, expression reliability in varied lighting, mode switching UX feel, scroll mode responsiveness

## Success Criteria

- Wink-to-click has <10% false positive rate and works reliably for left and right winks
- Mode switches (smile, brow raise, mouth open) activate within 500ms of the expression being held
- Head tilt fine cursor allows targeting elements within 10px precision
- Scroll mode provides smooth, controllable scrolling with no drift at rest
- HUD minimal pill is unobtrusive and doesn't interfere with work
- Expression baseline calibration completes within 2 seconds of tracking start
- Total frame processing time remains <30ms with expression detection added
