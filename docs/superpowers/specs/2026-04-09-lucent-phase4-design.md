# Lucent Phase 4: Air Typing / Virtual Keyboard

**Date:** 2026-04-09
**Status:** Draft
**Scope:** Phase 4 of 5 -- virtual keyboard controlled by hand tracking + eye gaze prediction selection
**Depends on:** Phase 1 (eye cursor + blink click), Phase 2 (expression detection, HUD), Phase 3 (hand tracking + gestures)

## Overview

Phase 4 adds a floating virtual on-screen keyboard controlled entirely by hand tracking and eye gaze. Users type by tapping fingers downward over a QWERTY layout, delete by swiping left, insert spaces with a thumb tap, and confirm with a fist. A prediction bar above the keyboard suggests word completions from a bundled frequency dictionary -- the user selects a suggestion by looking at it (eye gaze) and blinking to accept.

**Goal:** A user can type text into any application using hand gestures over a floating virtual keyboard, with word prediction for faster input, all without touching a physical keyboard.

**Non-goals for Phase 4:**
- Custom keyboard layouts (Dvorak, international) -- future
- ML-based language model or networked prediction -- Phase 4 uses local dictionary only
- Multi-hand typing (both hands simultaneously hitting different keys) -- future
- Swipe-to-type / gesture typing path -- future
- Custom gesture mapping editor UI (Phase 5)

## New InputMode: keyboard

A new `InputMode.keyboard` case is added to the existing `InputMode` enum. Activation and deactivation:

- **Activate:** Global hotkey `Cmd+Shift+K` (keyCode `0x28`, the `K` key)
- **Deactivate:** Same hotkey `Cmd+Shift+K` toggles back to `.normal`, or a fist-hold for >1 second while in keyboard mode also exits

When `.keyboard` mode is active:
- Hand tracking drives typing (TapDetector + KeyResolver + TypingSession)
- Eye tracking selects prediction bar suggestions
- Blink accepts the currently eye-selected prediction
- Face expressions (wink left/right) still fire their normal actions
- Scroll mode, dictation, and command palette are unavailable (hotkey is ignored for those modes while in keyboard mode)

The `ModeEvent` enum gains a new case to support keyboard mode transitions:
```
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

## Component 1: VirtualKeyboard (Model)

### Purpose
Defines the QWERTY key layout data structure. Pure data -- no UI, no detection logic.

### Location
`Sources/LucentCore/Models/VirtualKeyboard.swift`

### Key Data Structure

```
public struct KeyDefinition: Sendable, Equatable {
    public let label: String           // Display label ("A", "Shift", "123")
    public let keyCode: UInt16         // macOS virtual key code for CGEvent
    public let position: CGPoint       // Normalized position in keyboard space (0..1, 0..1)
    public let size: CGSize            // Normalized size in keyboard space
    public let row: Int                // Row index (0 = top/number row, 1-3 = letter rows)
}

public struct VirtualKeyboard: Sendable {
    public let keys: [KeyDefinition]
    public let rows: Int               // 4 rows: QWERTY standard
    public let columns: Int            // max keys in widest row (10)

    public static let qwerty: VirtualKeyboard  // Factory for standard layout
}
```

### Layout

Standard 4-row QWERTY with letter keys only (no number row in v1). Each row is horizontally centered with standard stagger offsets:

| Row | Keys | Stagger (normalized X offset) |
|-----|------|------|
| 0 | Q W E R T Y U I O P | 0.0 |
| 1 | A S D F G H J K L | 0.05 |
| 2 | Z X C V B N M | 0.15 |
| 3 | [space bar spanning 60% width] | 0.2 |

Each letter key occupies a normalized cell of `0.1 x 0.25` (width x height) in keyboard space. The space bar is `0.6 x 0.25`. Positions are computed from row/column index plus stagger.

### Key Codes

Standard macOS virtual key codes (used by `InputController.pressKey()`):

| Key | keyCode | Key | keyCode |
|-----|---------|-----|---------|
| A | 0x00 | N | 0x2D |
| B | 0x0B | O | 0x1F |
| C | 0x08 | P | 0x23 |
| D | 0x02 | Q | 0x0C |
| E | 0x0E | R | 0x0F |
| F | 0x03 | S | 0x01 |
| G | 0x05 | T | 0x11 |
| H | 0x04 | U | 0x20 |
| I | 0x22 | V | 0x09 |
| J | 0x26 | W | 0x0D |
| K | 0x28 | X | 0x07 |
| L | 0x25 | Y | 0x10 |
| M | 0x2E | Z | 0x06 |
| Space | 0x31 | Return | 0x24 |
| Delete | 0x33 | | |

## Component 2: TapDetector

### Purpose
Detects a downward finger tap gesture from hand landmark data. A "tap" is when a fingertip Y-coordinate drops below a dynamic threshold and then rises back up, mimicking a physical key press motion.

### Location
`Sources/LucentCore/Tracking/TapDetector.swift`

### Detection Algorithm

1. Track the index fingertip (`HandJoint.indexTip`) Y position across frames
2. Compute a running baseline Y from the last 10 frames (average Y when not tapping)
3. **Tap down:** fingertip Y drops more than `tapThreshold` (default: 0.04 normalized) below baseline
4. **Tap up:** fingertip Y rises back within `tapThreshold * 0.5` of baseline
5. A complete tap = down followed by up within `maxTapDuration` (default: 400ms)
6. After a tap fires, enter cooldown for `tapCooldown` (default: 150ms) to prevent double-fires

### Configuration

```
public struct TapConfig: Sendable {
    public var tapThreshold: Double         // 0.04 -- min Y displacement for tap-down
    public var returnThreshold: Double      // 0.02 -- max Y displacement from baseline for tap-up
    public var maxTapDuration: Double       // 0.4 seconds
    public var tapCooldown: Double          // 0.15 seconds
    public var baselineWindowSize: Int      // 10 frames
    public var minimumConfidence: Float     // 0.5 -- reject low-confidence hand data

    public static let defaults: TapConfig
}
```

### Noise Filtering

- Reject hand data with confidence < `minimumConfidence`
- Require at least `baselineWindowSize` frames of baseline data before first tap can fire
- If the hand disappears (no hand data) for >500ms, reset the baseline

### Output

```
public struct TapEvent: Sendable, Equatable {
    public let fingertipPosition: CGPoint  // Screen-space position at moment of tap
    public let timestamp: Double
}
```

### API

```
public final class TapDetector: @unchecked Sendable {
    public init(config: TapConfig = .defaults)
    public func update(handData: HandData) -> TapEvent?
    public func reset()
}
```

## Component 3: KeyResolver

### Purpose
Maps a fingertip position (in screen space) to the virtual key being hovered or tapped. Uses fuzzy matching to find the nearest key within a configurable radius.

### Location
`Sources/LucentCore/Tracking/KeyResolver.swift`

### Algorithm

1. Convert fingertip screen position to keyboard-local normalized coordinates:
   - `localX = (screenX - keyboardOrigin.x) / keyboardSize.width`
   - `localY = (screenY - keyboardOrigin.y) / keyboardSize.height`
2. If `localX` or `localY` is outside `[-fuzzyMargin, 1+fuzzyMargin]`, return nil (finger is outside keyboard bounds)
3. Find the key whose center is nearest to `(localX, localY)`
4. If the distance to the nearest key center exceeds `maxHitRadius` (default: 0.08 normalized), return nil
5. Return the matched `KeyDefinition`

### Configuration

```
public struct KeyResolverConfig: Sendable {
    public var fuzzyMargin: Double     // 0.05 -- how far outside keyboard bounds to still match
    public var maxHitRadius: Double    // 0.08 -- max distance from key center to count as hit
    public static let defaults: KeyResolverConfig
}
```

### API

```
public final class KeyResolver: Sendable {
    public let keyboard: VirtualKeyboard

    public init(keyboard: VirtualKeyboard = .qwerty, config: KeyResolverConfig = .defaults)

    /// Returns the key at the given position, or nil if outside bounds / too far from any key.
    /// keyboardFrame: the screen-space rect of the keyboard overlay.
    /// fingertipScreenPosition: the screen-space position of the fingertip.
    public func resolve(
        fingertipScreenPosition: CGPoint,
        keyboardFrame: CGRect
    ) -> KeyDefinition?

    /// Returns the key nearest to the given keyboard-local normalized position.
    /// Used internally and by UI for hover highlighting.
    public func nearestKey(localPosition: CGPoint) -> (key: KeyDefinition, distance: Double)?
}
```

## Component 4: PredictionEngine

### Purpose
Simple prefix-based word completion. Loads a bundled frequency dictionary and returns top matches for a given prefix.

### Location
`Sources/LucentCore/Control/PredictionEngine.swift`

### Dictionary Format

Bundled resource file `words.txt` at `Sources/LucentCore/Resources/words.txt`. Format is one entry per line:
```
the	23135851162
of	13151942776
and	12997637966
to	12136980858
...
```

Tab-separated: word, then frequency count. File contains the 10,000 most common English words sorted by frequency (the implementation plan bundles a representative 500-word subset; the full 10K file is added before release).

### Algorithm

1. On init, load `words.txt` from the bundle, parse into `[(word: String, frequency: Int)]`, sort by frequency descending
2. For a given prefix (case-insensitive), filter to words starting with that prefix
3. Return the top 3 by frequency
4. If prefix is empty, return empty array
5. If prefix is a complete word, still return completions (words that start with it and are longer), plus the exact match if it exists

### API

```
public final class PredictionEngine: Sendable {
    public init()  // loads dictionary from bundle

    /// For testability: init with explicit word list
    public init(words: [(word: String, frequency: Int)])

    /// Returns up to `maxResults` word completions for the given prefix, sorted by frequency.
    public func predict(prefix: String, maxResults: Int = 3) -> [String]
}
```

### Performance

The dictionary is small (10K entries). A linear scan with prefix matching is fast enough (<1ms). No trie or other data structure needed for v1.

## Component 5: TypingSession

### Purpose
Manages the text buffer during keyboard mode. Receives tap events resolved to keys, handles special actions (backspace, space, enter), maintains the current word being typed, and posts keystrokes to the OS via `InputController.pressKey()`.

### Location
`Sources/LucentCore/Control/TypingSession.swift`

### State

```
public final class TypingSession: @unchecked Sendable {
    public private(set) var buffer: String          // Full text typed this session
    public private(set) var currentWord: String     // Current word being typed (since last space/enter)
    public private(set) var isActive: Bool

    private let inputController: InputController
    private let predictionEngine: PredictionEngine
}
```

### Actions

| Action | Trigger | Behavior |
|--------|---------|----------|
| Character | TapDetector fires + KeyResolver returns a letter key | Append to `currentWord`, post `pressKey(keyCode:)` |
| Backspace | Swipe left detected while in keyboard mode (reuses existing `swipeLeft` gesture, but action is remapped in keyboard mode) | Remove last character from `currentWord` (or `buffer` if `currentWord` is empty), post `pressKey(keyCode: 0x33)` |
| Space | Thumb tap -- thumb is extended while index+middle+ring+little are all curled, detected by checking `fingerStates` | Append `currentWord` to `buffer` + space, reset `currentWord`, post `pressKey(keyCode: 0x31)` |
| Enter | Fist gesture (all fingers curled) held for 300ms while in keyboard mode | Post `pressKey(keyCode: 0x24)`, append newline to buffer, reset `currentWord` |
| Accept prediction | Blink while eye gaze is on a prediction bar item | Delete `currentWord.count` characters via backspace, type the full predicted word, update buffer |

### Accept Prediction Detail

When a prediction is accepted:
1. Post `pressKey(keyCode: 0x33)` (delete/backspace) repeated `currentWord.count` times to erase the partial word
2. For each character in the predicted word, post `pressKey(keyCode:)` with the corresponding key code
3. Post `pressKey(keyCode: 0x31)` (space) to complete the word
4. Update `buffer` and reset `currentWord`

### API

```
public final class TypingSession: @unchecked Sendable {
    public init(inputController: InputController, predictionEngine: PredictionEngine)

    public func start()
    public func stop()

    public func typeCharacter(_ key: KeyDefinition)
    public func backspace()
    public func space()
    public func enter()
    public func acceptPrediction(_ word: String)

    public func currentPredictions() -> [String]

    public func reset()
}
```

## Component 6: KeyboardOverlay (UI)

### Purpose
A floating NSPanel at the bottom of the screen showing the QWERTY layout. The key under the user's fingertip is highlighted. Semi-transparent, always-on-top, click-through (does not steal focus from the target application).

### Location
`App/UI/KeyboardOverlay.swift`

### Panel Properties

Built on `NSPanel`, same pattern as `HUDPanel`:
- **Size:** 600 x 200 points
- **Position:** Horizontally centered at screen bottom, 20pt above dock
- **Level:** `.floating`
- **Style:** `.nonactivatingPanel`, `.fullSizeContentView`
- **Behavior:** `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
- **Background:** Semi-transparent dark (`NSColor.black.withAlphaComponent(0.75)`)
- **Corner radius:** 16pt

### Key Rendering

Each key is drawn as a rounded rectangle:
- **Normal state:** `Color.white.opacity(0.15)` fill, white label text
- **Hovered state:** `Color.blue.opacity(0.6)` fill, white bold label text -- follows fingertip position
- **Tapped state:** Brief `Color.green.opacity(0.8)` flash for 100ms after tap fires

Labels are rendered in `system` font, size 18pt for letter keys, 14pt for space bar label.

### Hover Tracking

The overlay receives the currently hovered `KeyDefinition?` from `TrackingPipeline` (via a published property). The SwiftUI view highlights whichever key matches.

### Visibility

- Shown when `InputMode` is `.keyboard`
- Hidden when mode changes away from `.keyboard`
- Animated fade-in/out (200ms)

## Component 7: PredictionBar (UI)

### Purpose
A horizontal bar of up to 3 word suggestions displayed directly above the KeyboardOverlay. The user selects a suggestion by looking at it (eye gaze maps to the bar region) and blinks to accept.

### Location
`App/UI/PredictionBar.swift`

### Layout

- **Size:** 600 x 40 points (same width as keyboard)
- **Position:** Directly above KeyboardOverlay (y = keyboard top + 4pt gap)
- **Background:** Semi-transparent dark, matching keyboard style
- **Items:** Up to 3 suggestion buttons, evenly spaced across the width (each ~200pt wide)

### Eye Gaze Selection

When the cursor (driven by eye gaze) enters a prediction item's bounds, that item becomes "selected" (highlighted with `Color.blue.opacity(0.4)` background). The selection follows gaze in real-time. When the user blinks (detected by `BlinkDetector`), the currently selected prediction is accepted via `TypingSession.acceptPrediction()`.

### Integration

- PredictionBar observes `TypingSession.currentPredictions()` for its content
- It observes `TrackingPipeline.currentCursorPosition` to determine which item is under the gaze
- When blink fires while gaze is on a prediction item, the pipeline calls `typingSession.acceptPrediction(word)`

### Empty State

When `currentWord` is empty or no predictions match, the bar shows "Start typing..." in gray text, centered.

## Pipeline Integration

### TrackingPipeline Changes

`TrackingPipeline` gains new state for keyboard mode:

```
// New published properties
@Published public var keyboardModeActive: Bool = false
@Published public var hoveredKey: KeyDefinition? = nil
@Published public var currentTypedWord: String = ""
@Published public var predictions: [String] = []
@Published public var selectedPredictionIndex: Int? = nil

// New private components
private var tapDetector: TapDetector?
private var keyResolver: KeyResolver?
private var typingSession: TypingSession?
private let predictionEngine = PredictionEngine()
```

### Frame Processing in Keyboard Mode

When `currentMode == .keyboard`, `handleFrame()` does the following:

1. **Eye tracking** continues as normal -- cursor moves, used for prediction selection
2. **Hand data** is routed to `TapDetector` instead of `GestureRecognizer`
3. If `TapDetector` returns a `TapEvent`:
   a. `KeyResolver.resolve()` maps the tap position to a key
   b. If a key is found, `TypingSession.typeCharacter()` posts the keystroke
4. Check `fingerStates` for space gesture (thumb extended, others curled):
   a. If detected, `TypingSession.space()`
5. Check for swipe-left gesture (reuse existing detection):
   a. If detected in keyboard mode, `TypingSession.backspace()`
6. Check for fist gesture:
   a. If detected and held 300ms in keyboard mode, `TypingSession.enter()`
7. Update `hoveredKey` from fingertip position (for UI highlight)
8. Update `predictions` from `TypingSession.currentPredictions()`
9. If blink detected and `selectedPredictionIndex` is set, accept that prediction

### Gesture Remapping in Keyboard Mode

Some gestures change meaning in keyboard mode:

| Gesture | Normal Mode | Keyboard Mode |
|---------|------------|---------------|
| Swipe left | Switch desktop left | Backspace |
| Fist (300ms) | Click-and-drag | Enter |
| Point | Precision cursor | (disabled -- tap detection uses index finger instead) |
| Pinch | Zoom | (disabled) |
| Swipe right/up/down | Desktop/Mission Control/Expose | (disabled) |
| Open palm | Toggle hand gestures | (disabled) |

### InputModeManager Changes

`InputModeManager` gains support for the `.keyboard` mode:

- Keyboard mode is **not** triggered by face expressions -- only by the `Cmd+Shift+K` hotkey
- While in keyboard mode, expression-based mode changes (mouthOpen for scroll, smile for dictation, browRaise for command palette) are suppressed
- Wink actions still fire (they pass through in all modes)
- The method `toggleKeyboardMode()` is added for the hotkey handler to call

### FrameProcessor Changes

No changes needed. `FrameProcessor` already outputs `hands: [HandData]` and `gestures: [GestureEvent]`. The keyboard-mode-specific processing (TapDetector, KeyResolver) lives in `TrackingPipeline`, not in `FrameProcessor`.

## AppState + MenuBar Updates

### AppState Changes

```
// New published state
@Published public var keyboardModeEnabled: Bool  // persisted in UserDefaults

// New hotkey registration
private var keyboardHotkeyRef: EventHotKeyRef?
// Registers Cmd+Shift+K (keyCode 0x28) with hotkey ID 3
```

New notification:
```
static let toggleKeyboard = Notification.Name("com.lucent.toggleKeyboard")
```

### MenuBarView Changes

Add a new toggle and keyboard mode indicator:
- Toggle: "Virtual Keyboard" -- enables/disables keyboard mode availability
- When keyboard mode is active, show a keyboard icon and "Keyboard Mode" label in the status area

### Mode Icon/Name Extensions

The `modeIcon` and `modeName` computed properties in `MenuBarView` gain a `.keyboard` case:
- Icon: `"keyboard"` (SF Symbol)
- Name: `"Keyboard Mode"`

## Dictionary Resource File

### Location
`Sources/LucentCore/Resources/words.txt`

### Format
Tab-separated values, one word per line:
```
word\tfrequency
```

Where frequency is an integer representing relative word frequency (higher = more common). The file contains the 10,000 most common English words. For development and testing, a 500-word subset is initially bundled.

### Bundle Access

The `Package.swift` target for `LucentCore` must declare the resource:
```
.target(
    name: "LucentCore",
    path: "Sources/LucentCore",
    resources: [.process("Resources")]
)
```

`PredictionEngine` loads the file via:
```
Bundle.module.url(forResource: "words", withExtension: "txt")
```

## New Files

| File | Location | Purpose |
|------|----------|---------|
| `VirtualKeyboard.swift` | `Sources/LucentCore/Models/` | QWERTY key layout data, KeyDefinition, key codes |
| `TapDetector.swift` | `Sources/LucentCore/Tracking/` | Finger tap detection from hand landmarks |
| `KeyResolver.swift` | `Sources/LucentCore/Tracking/` | Map fingertip position to keyboard key |
| `PredictionEngine.swift` | `Sources/LucentCore/Control/` | Prefix-based word completion from dictionary |
| `TypingSession.swift` | `Sources/LucentCore/Control/` | Text buffer management, keystroke posting |
| `KeyboardOverlay.swift` | `App/UI/` | Floating NSPanel with QWERTY key display |
| `PredictionBar.swift` | `App/UI/` | Word suggestion bar above keyboard |
| `words.txt` | `Sources/LucentCore/Resources/` | Frequency dictionary (10K words) |
| `TapDetectorTests.swift` | `Tests/LucentCoreTests/` | Tap detection unit tests |
| `KeyResolverTests.swift` | `Tests/LucentCoreTests/` | Key resolution unit tests |
| `PredictionEngineTests.swift` | `Tests/LucentCoreTests/` | Prediction unit tests |
| `TypingSessionTests.swift` | `Tests/LucentCoreTests/` | Typing session unit tests |
| `VirtualKeyboardTests.swift` | `Tests/LucentCoreTests/` | Keyboard layout unit tests |

## Modified Files

| File | Change |
|------|--------|
| `InputMode.swift` | Add `.keyboard` case to `InputMode` enum; add `KeyboardActionType` enum |
| `InputModeManager.swift` | Add `toggleKeyboardMode()`, suppress other mode changes during keyboard mode |
| `TrackingPipeline.swift` | Add keyboard mode frame handling, TapDetector/KeyResolver/TypingSession wiring |
| `AppState.swift` | Add `keyboardModeEnabled`, register `Cmd+Shift+K` hotkey, keyboard notification |
| `MenuBarView.swift` | Add "Virtual Keyboard" toggle, keyboard mode icon/name |
| `Package.swift` | Add `resources: [.process("Resources")]` to LucentCore target |

## Testing Strategy

- **TapDetector (TDD):** Synthetic hand data sequences with controlled Y positions. Test tap detection, cooldown, noise rejection, baseline reset on hand loss.
- **KeyResolver (TDD):** Known keyboard frames and fingertip positions. Test exact hits, nearest-key fuzzy matching, out-of-bounds rejection, edge keys.
- **PredictionEngine (TDD):** Known dictionary, test prefix matching, frequency ordering, empty prefix, exact match behavior, case insensitivity.
- **TypingSession (TDD):** Mock InputController to capture posted keyCodes. Test character typing, backspace, space, enter, prediction acceptance sequence.
- **VirtualKeyboard:** Verify key count, no overlapping positions, all key codes are valid, row layout correctness.
- **Manual testing:** End-to-end typing flow, keyboard overlay visibility, prediction bar interaction, hotkey toggle, mode transitions.

## Success Criteria

- Tap detection latency < 50ms from finger motion to keystroke posted
- Key resolution accuracy > 95% (correct key identified for intended taps)
- Prediction engine returns results in < 5ms
- Keyboard overlay renders at 60fps with no dropped frames
- Typing speed of at least 10 WPM achievable by a practiced user
- No interference with normal mode when keyboard mode is inactive
- Clean mode transitions: entering/exiting keyboard mode preserves cursor position and face tracking state
- Memory overhead of dictionary < 2MB
