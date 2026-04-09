# Lucent Phase 3: Hand Tracking + Gestures

**Date:** 2026-04-09
**Status:** Draft
**Scope:** Phase 3 of 5 — hand landmark detection, gesture recognition, OS action mapping
**Depends on:** Phase 1 (eye cursor), Phase 2 (expression detection, HUD)

## Overview

Phase 3 adds hand tracking via Apple Vision's `VNDetectHumanHandPoseRequest`. Users can swipe to switch desktops, pinch to zoom, make a fist to drag, point to precision-control the cursor, and use an open palm to pause gesture recognition. Hand gestures work simultaneously with eye/face tracking — they're additive, not modal.

**Goal:** A user can perform common macOS window management and navigation actions using hand gestures in front of the webcam, alongside existing eye and face controls.

**Non-goals for Phase 3:**
- Air typing / virtual keyboard (Phase 4)
- Custom gesture mapping editor UI (Phase 5)
- Multi-hand gesture combinations (future)

## Approach

Apple Vision `VNDetectHumanHandPoseRequest` — 21 landmarks per hand (wrist + 4 joints × 5 fingers), runs in the same `VNImageRequestHandler` as face detection. Finger states (extended/curled) computed from joint angles. Gesture classification from finger states + inter-frame movement tracking.

## Hand Detection

### HandDetector

New component in `Sources/LucentCore/Tracking/`. Wraps `VNDetectHumanHandPoseRequest`.

**Output — HandData:**

```
public struct HandData: Sendable {
    public let landmarks: [HandJoint: CGPoint]  // 21 joints, normalized 0..1
    public let fingerStates: [Finger: FingerState]  // 5 fingers
    public let wristPosition: CGPoint
    public let chirality: Chirality  // .left or .right
    public let confidence: Float
}

public enum Finger: CaseIterable, Sendable { case thumb, index, middle, ring, little }
public enum FingerState: Sendable { case extended, curled }
public enum Chirality: Sendable { case left, right }
public enum HandJoint: String, CaseIterable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}
```

### Finger State Classification

A finger is **extended** if the angle at the PIP joint (MCP → PIP → TIP) is greater than 150°. It is **curled** if less than 150°. For thumb, use CMC → MP → TIP angle with a threshold of 140° (thumb has different geometry).

The angle is computed via dot product of the two vectors forming the joint.

### Hand Movement Tracking

HandDetector stores the previous frame's wrist position and computes:
- `velocity: CGPoint` — displacement per frame in normalized coordinates
- `movementDirection: SwipeDirection?` — `.left, .right, .up, .down` if velocity exceeds threshold

## Gesture Recognition

### GestureRecognizer

New component in `Sources/LucentCore/Tracking/`. Takes `HandData` (current + history) and emits `GestureEvent`s.

### Gesture Definitions

| Gesture | Hand Pose | Movement | Hold Duration | Type |
|---|---|---|---|---|
| Swipe left | All fingers extended | Wrist moves >30% frame width leftward in <500ms | One-shot | One-shot |
| Swipe right | All fingers extended | Wrist moves >30% frame width rightward in <500ms | One-shot | One-shot |
| Swipe up | All fingers extended | Wrist moves >25% frame height upward in <500ms | One-shot | One-shot |
| Swipe down | All fingers extended | Wrist moves >25% frame height downward in <500ms | One-shot | One-shot |
| Pinch | Thumb-index distance < 0.03 normalized, middle+ring+little extended | Continuous while held | 0ms (immediate) | Continuous |
| Fist | All 5 fingers curled | None required | 300ms | Continuous |
| Point | Index extended, all others curled | None required | 200ms | Continuous |
| Open palm | All 5 extended, stationary (velocity < threshold) | Held still for 500ms | 500ms | Toggle |

### Gesture Event Types

```
public enum GestureType: String, Codable, Sendable, CaseIterable {
    case swipeLeft, swipeRight, swipeUp, swipeDown
    case pinch, fist, point, openPalm
}

public struct GestureEvent: Sendable, Equatable {
    public let type: GestureType
    public let state: GestureState
    public let timestamp: Double
}

public enum GestureState: Sendable, Equatable {
    case began
    case changed(value: Double)  // for pinch: distance; for point: position
    case ended
    case discrete  // for one-shot gestures (swipes)
}
```

### Swipe Detection

Swipe detection uses a sliding window of wrist positions over the last 500ms (15 frames at 30fps). When the total displacement exceeds the threshold and all fingers were extended throughout, a swipe gesture fires. After firing, the window resets and enters a 500ms cooldown.

### Pinch Distance Tracking

When pinch is active (thumb-index distance < 0.03), the `changed` state reports the current thumb-index distance. The pipeline maps increasing distance to zoom-in and decreasing to zoom-out, using the delta between frames.

### Fist Drag

When fist is detected and held for 300ms, a `began` event fires. The pipeline starts a click-and-drag at the current cursor position. While fist is held, cursor movement from eye tracking is interpreted as drag movement. On fist release (any finger extends), `ended` fires and the drag releases.

### Point Precision

When point is detected, the index fingertip position directly controls the cursor (overriding eye gaze). The normalized fingertip position maps to screen coordinates. This provides fine motor control when eye gaze isn't precise enough.

## OS Action Mapping

| Gesture | macOS Action | Implementation |
|---|---|---|
| Swipe left | Switch desktop left | `Ctrl+Left` via InputController.pressKey |
| Swipe right | Switch desktop right | `Ctrl+Right` via InputController.pressKey |
| Swipe up | Mission Control | `Ctrl+Up` via InputController.pressKey |
| Swipe down | App Exposé | `Ctrl+Down` via InputController.pressKey |
| Pinch open | Zoom in | `Cmd+Plus` via InputController.pressKey |
| Pinch close | Zoom out | `Cmd+Minus` via InputController.pressKey |
| Fist | Click-and-drag | InputController.startDrag / endDrag |
| Point | Direct cursor control | InputController.moveCursor |
| Open palm | Pause/resume hand gestures | Internal toggle, no OS event |

## Pipeline Integration

### Camera + Detection

`HandDetector` runs `VNDetectHumanHandPoseRequest` on the same `CVPixelBuffer` already captured by CameraManager. It runs in the `FrameProcessor.process()` method alongside face detection — both Vision requests can be submitted to the same `VNImageRequestHandler`.

### FrameResult Expansion

`FrameProcessor.FrameResult` adds:
- `hands: [HandData]` — 0, 1, or 2 detected hands
- `gestures: [GestureEvent]` — gesture events from this frame

### TrackingPipeline Changes

`handleFrame()` processes gesture events after expression events:
- Swipe gestures → dispatch OS key combos
- Pinch → track delta, dispatch zoom
- Fist → manage drag state (mouseDown on begin, mouseUp on end)
- Point → override cursor position from fingertip
- Open palm → toggle `handGesturesEnabled` flag

Hand gestures and eye/face tracking run simultaneously. During point gesture, eye-gaze cursor is suppressed and fingertip controls cursor. During fist drag, cursor source (eye or point) continues but mouseDown is held.

### InputController Additions

```
public func startDrag(at point: GazePoint)   // mouseDown
public func endDrag(at point: GazePoint)      // mouseUp
public func switchDesktop(direction: SwipeDirection)  // Ctrl+Arrow
public func triggerMissionControl()           // Ctrl+Up
public func triggerExpose()                   // Ctrl+Down
public func zoom(direction: ZoomDirection)    // Cmd+Plus or Cmd+Minus
```

Where `SwipeDirection` is `.left, .right` and `ZoomDirection` is `.zoomIn, .zoomOut`.

## HUD Updates

- HUDMinimalView gains a hand icon when hand tracking is active (shows detected gesture type)
- HUDExpandedView shows hand landmark count and active gesture name
- MenuBarView gets a "Hand Gestures" toggle

## New Files

| File | Location | Purpose |
|---|---|---|
| `HandDetector.swift` | `Sources/LucentCore/Tracking/` | VNDetectHumanHandPoseRequest wrapper, finger state, movement |
| `GestureRecognizer.swift` | `Sources/LucentCore/Tracking/` | Gesture classification from hand data |
| `GestureType.swift` | `Sources/LucentCore/Models/` | GestureType, GestureEvent, GestureState, GestureConfig, HandData types |
| `HandDetectorTests.swift` | `Tests/LucentCoreTests/` | Finger state classification tests |
| `GestureRecognizerTests.swift` | `Tests/LucentCoreTests/` | Gesture detection tests |

## Modified Files

| File | Change |
|---|---|
| `FrameProcessor.swift` | Add HandDetector + GestureRecognizer; expand FrameResult with hands + gestures |
| `InputController.swift` | Add startDrag, endDrag, switchDesktop, triggerMissionControl, triggerExpose, zoom |
| `TrackingPipeline.swift` | Handle gesture events, point override, fist drag state |
| `HUDMinimalView.swift` | Show hand/gesture icon |
| `HUDExpandedView.swift` | Show hand count + gesture name |
| `MenuBarView.swift` | Hand gestures toggle |
| `AppState.swift` | handGesturesEnabled state |

## Testing Strategy

- **Unit tests:** HandDetector finger state classification (synthetic joint angles → extended/curled), GestureRecognizer (synthetic hand position sequences → correct gesture events, swipe direction, cooldown)
- **Manual testing:** Gesture responsiveness, swipe accuracy, pinch zoom feel, fist drag precision, point cursor mode, multi-hand handling

## Success Criteria

- Hand landmarks detected at 30fps with <20ms added latency
- Swipe gestures recognized within 500ms of motion completion
- Fist-to-drag works reliably with <10% false positive rate
- Point gesture provides precise cursor control within 20px accuracy
- Hand gestures don't interfere with face/eye tracking performance
- CPU usage stays below 25% total (face + hand tracking combined)
