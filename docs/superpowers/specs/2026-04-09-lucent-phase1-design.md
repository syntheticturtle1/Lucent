# Lucent Phase 1: Eye Cursor + Blink Click

**Date:** 2026-04-09
**Status:** Draft
**Scope:** Phase 1 of 5 — MVP eye-based cursor control with blink-to-click

## Overview

Lucent is a macOS application that replaces mouse and keyboard input with vision-based body tracking. Phase 1 delivers eye-controlled cursor movement and blink-to-click — the foundational tracking engine that all subsequent phases build on.

**Goal:** A user can move the macOS cursor with their eyes and click by blinking, using only a standard webcam, with low enough latency and high enough accuracy to be genuinely usable for daily work.

**Non-goals for Phase 1:**
- Face expression recognition beyond blinks (Phase 2)
- Hand tracking and gestures (Phase 3)
- Air typing / virtual keyboard (Phase 4)
- Full settings UI, system preference pane, profiles (Phase 5)

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI (menu bar app)
- **Camera:** AVFoundation
- **Face/Eye Detection:** Apple Vision framework (`VNDetectFaceLandmarksRequest`)
- **Gaze Estimation:** CoreML model (based on GazeCapture/iTracker architecture)
- **OS Input:** CGEvent API (Accessibility framework)
- **Target:** macOS 14+ (Sonoma), Apple Silicon and Intel

## Architecture

```
Camera (AVFoundation)
  → FrameProcessor (pixel buffer prep, eye region cropping)
    → FaceLandmarkDetector (Apple Vision, 76 landmarks)
    → GazeEstimator (CoreML, eye crops + head pose → gaze point)
      → CalibrationEngine (raw gaze → screen coordinates)
        → CursorSmoother (Kalman filter + dwell zones)
          → InputController (CGEvent cursor moves + clicks)

BlinkDetector (eye aspect ratio from landmarks → click events → InputController)

App Shell (SwiftUI menu bar app + calibration overlay + settings window)
```

### Component Responsibilities

| Component | Purpose | Framework |
|---|---|---|
| CameraManager | AVCaptureSession at 30fps 640x480, delivers CMSampleBuffer on dedicated serial queue | AVFoundation |
| FrameProcessor | Converts CMSampleBuffer to CVPixelBuffer, passes to FaceLandmarkDetector, then crops left eye / right eye / face regions using detected landmark positions | CoreGraphics |
| FaceLandmarkDetector | Extracts 76 facial landmarks per frame, derives head pose (pitch/yaw/roll) from landmark geometry | Apple Vision |
| GazeEstimator | CoreML model: inputs are left eye crop (224x224), right eye crop (224x224), head pose (3 floats), face grid (25x25 binary mask). Outputs (x, y) gaze point in normalized camera coordinates. Runs on Neural Engine. Target: <5ms inference | CoreML |
| CalibrationEngine | Maps raw gaze coordinates to screen coordinates via 2nd-degree polynomial regression. Trained from 9-point calibration data | Accelerate |
| CursorSmoother | Kalman filter for jitter removal. Dwell zone locking (>200ms in small radius locks to centroid). Velocity scaling (saccades get less smoothing, micro-movements get more) | Custom |
| InputController | Posts cursor position updates and click events to macOS via CGEvent API | CoreGraphics |
| BlinkDetector | Computes Eye Aspect Ratio (EAR) from Vision landmarks, classifies blink types by duration | Custom |

### Data Flow Timing

All processing happens off the main thread on a dedicated serial dispatch queue. Target end-to-end latency from camera frame capture to cursor update: **<30ms** (one frame of latency at 30fps).

## Camera Pipeline

- `AVCaptureSession` configured for 640x480 at 30fps — sufficient resolution for eye tracking while keeping processing cheap
- Frames delivered as `CMSampleBuffer` on a dedicated serial dispatch queue
- FrameProcessor converts `CMSampleBuffer` to `CVPixelBuffer`, passes it to FaceLandmarkDetector, then uses the returned landmark positions to crop eye regions and face region as separate buffers for the gaze model
- All processing off main thread — UI never blocks

## Face Landmark Detection

- `VNDetectFaceLandmarksRequest` provides 76 facial landmarks per frame
- Key landmarks used: eye contours (8 points each), pupil centers, nose tip, face contour
- Head pose (pitch, yaw, roll) derived from landmark geometry using a standard PnP solve with known face proportions
- If no face detected for 500ms, tracking pauses — cursor freezes at last known position rather than jumping

## Gaze Estimation Model

- CoreML model based on the GazeCapture/iTracker architecture
- **Inputs:**
  - Left eye crop: 224x224 RGB
  - Right eye crop: 224x224 RGB
  - Head pose: 3 floats (pitch, yaw, roll in radians)
  - Face grid: 25x25 binary mask indicating face position within the full camera frame
- **Output:** (x, y) gaze point in normalized camera coordinates
- Runs on Neural Engine (Apple Silicon) or GPU (Intel) via CoreML
- Model source: open-source GazeCapture dataset trained model, converted to CoreML format using `coremltools`
- Target inference latency: <5ms on Apple Silicon

## Calibration System

### Full Calibration (9-point)

- Fullscreen borderless window renders above all content
- Displays a dot that moves sequentially to 9 positions: 4 corners, 4 edge midpoints, center
- User looks at each dot for ~2 seconds
- Collects ~60 gaze samples per point (30fps x 2s)
- Outlier rejection: discards samples >2 standard deviations from the mean per point
- Builds a 2nd-degree polynomial regression mapping from raw gaze coordinates to screen pixel coordinates
- Handles nonlinear distortion between camera gaze and actual screen position

### Quick Recalibration (3-point)

- Uses center + two diagonal corners
- Adjusts the existing polynomial mapping rather than rebuilding from scratch
- For when accuracy drifts due to posture shifts

### Calibration Persistence

- Profile saved to `~/Library/Application Support/Lucent/calibration.json`
- Contains: polynomial coefficients, camera identifier, timestamp
- Loaded automatically on launch — no recalibration needed if same camera and similar position
- Auto-invalidates if camera device changes

### Calibration UI

- Progress ring around the target dot fills as samples are collected
- After completion, briefly displays an accuracy heatmap (green = accurate, red = less accurate regions) before dismissing

## Cursor Smoothing

### Kalman Filter

Primary smoother that predicts where gaze is heading and blends prediction with measurement. Tuned for low latency (cursor tracks quickly) while suppressing high-frequency jitter.

### Dwell Zone

When gaze stays within a configurable radius (default: 30px) for >200ms, cursor locks to the centroid of that region. Prevents the cursor from vibrating when the user is trying to hold still on a target. Exits the dwell zone when gaze moves beyond the radius.

### Velocity Scaling

- Large, fast eye movements (saccades) receive less smoothing so the cursor keeps up
- Small micro-movements receive heavier smoothing for precision
- Transition between modes is continuous, not binary

## Blink Detection

### Eye Aspect Ratio (EAR)

EAR = ratio of vertical eye opening to horizontal eye width, computed from Vision landmarks. Drops from ~0.3 (open) to ~0.05 (closed) during a blink.

### Click Classification

| Blink Pattern | Duration | Action |
|---|---|---|
| Quick blink | <300ms | Left click |
| Long blink | 300ms–800ms | Right click |
| Double blink | Two quick blinks within 500ms | Double click |

### Natural Blink Filtering

Involuntary blinks occur every 3-5 seconds. The detector distinguishes intentional from natural blinks by:
- Comparing left vs right EAR (intentional blinks are often asymmetric or exaggerated)
- Measuring blink sharpness (how quickly EAR drops — intentional blinks are sharper)
- Applying a 200ms cooldown after each registered click to prevent accidental double-triggers

All thresholds are configurable in settings.

### Feedback

Optional audible click sound and/or visual indicator when a click registers, so the user has confirmation the action was received.

## Error Handling

| Scenario | Behavior |
|---|---|
| Face lost | Cursor freezes at last position. Menu bar icon changes to indicate paused. Resumes automatically when face reappears |
| Poor lighting | If landmark confidence drops below threshold, smoothing increases aggressively. Persistent low confidence triggers a notification suggesting better lighting |
| Multiple faces | Locks to the first detected face, ignores others. If primary face lost and another appears, does NOT switch — waits for original |
| Camera permission denied | First launch triggers macOS camera permission dialog. If denied, shows explanation with button to open System Settings > Privacy > Camera |
| Accessibility permission missing | CGEvent requires Accessibility access. App detects if missing and guides user to grant it in System Settings > Privacy > Accessibility |
| Camera disconnected | Tracking pauses, notification shown. Resumes when camera reconnects |

## App Shell

### Menu Bar

- Eye icon in menu bar: filled when tracking active, outlined when paused
- Click opens popover with:
  - On/off toggle
  - Tracking status (face detected / calibrated / active)
  - Quick recalibrate button
  - Open settings link

### Global Shortcut

- Default: `Cmd+Shift+L` to toggle tracking on/off
- Essential escape hatch if eye tracking behaves unexpectedly
- Customizable in settings

### Launch at Login

- Uses `SMAppService` (modern macOS launch-at-login API)
- Configurable in settings, default off

### Settings Window

| Tab | Contents |
|---|---|
| General | Launch at login, global shortcut customization, pause when screen locks |
| Tracking | Camera selection dropdown, frame rate (15/30fps), gaze model selection |
| Cursor | Smoothing strength slider, dwell zone radius, velocity scaling, cursor speed multiplier |
| Click | Blink duration thresholds with live EAR preview, natural blink filter sensitivity, click sound toggle |
| Calibration | Run full calibration, run quick recal, accuracy heatmap, auto-recalibrate interval |

### First Launch Wizard

Walks the user through:
1. Camera permission grant
2. Accessibility permission grant
3. Full 9-point calibration
4. Brief tutorial (move eyes to move cursor, blink to click)

## macOS Integration

- **Permissions required:** Camera (AVFoundation), Accessibility (CGEvent)
- **Entitlements:** App Sandbox with camera + accessibility exceptions
- **Distribution:** Notarized `.app` bundle (not App Store — Accessibility entitlement is restricted on App Store)
- **Minimum OS:** macOS 14 Sonoma
- **Hardware:** Apple Silicon (Neural Engine) and Intel (GPU fallback for CoreML)

## Project Structure

```
Lucent/
├── Lucent.xcodeproj
├── Sources/
│   ├── App/
│   │   ├── LucentApp.swift              # App entry point, menu bar setup
│   │   ├── AppState.swift               # Global app state (ObservableObject)
│   │   └── Permissions.swift            # Camera + Accessibility permission checks
│   ├── Camera/
│   │   ├── CameraManager.swift          # AVCaptureSession management
│   │   └── FrameProcessor.swift         # Pixel buffer prep, eye cropping
│   ├── Tracking/
│   │   ├── FaceLandmarkDetector.swift   # Vision framework face landmarks
│   │   ├── GazeEstimator.swift          # CoreML gaze model wrapper
│   │   └── BlinkDetector.swift          # EAR-based blink classification
│   ├── Control/
│   │   ├── CalibrationEngine.swift      # 9-point calibration + polynomial mapping
│   │   ├── CursorSmoother.swift         # Kalman filter + dwell zones
│   │   └── InputController.swift        # CGEvent cursor + click posting
│   ├── UI/
│   │   ├── MenuBarView.swift            # Menu bar popover
│   │   ├── SettingsView.swift           # Settings window (tabbed)
│   │   ├── CalibrationOverlay.swift     # Fullscreen calibration UI
│   │   └── FirstLaunchWizard.swift      # Permission + calibration onboarding
│   └── Models/
│       ├── GazePoint.swift              # Gaze coordinate types
│       ├── CalibrationProfile.swift     # Calibration data model
│       └── TrackingState.swift          # Enum for tracking status
├── Resources/
│   ├── GazeModel.mlmodel               # CoreML gaze estimation model
│   └── Assets.xcassets                  # App icon, menu bar icons
└── Tests/
    ├── CalibrationEngineTests.swift
    ├── CursorSmootherTests.swift
    ├── BlinkDetectorTests.swift
    └── GazeEstimatorTests.swift
```

## Testing Strategy

- **Unit tests:** CalibrationEngine (polynomial fitting accuracy), CursorSmoother (filter behavior with synthetic data), BlinkDetector (EAR classification with known sequences)
- **Integration tests:** Camera → Landmark → Gaze pipeline with recorded video frames
- **Manual testing:** Calibration flow UX, cursor usability across screen regions, blink reliability in varied lighting
- **Performance tests:** End-to-end latency measurement (frame timestamp to CGEvent post), CPU/GPU usage profiling

## Success Criteria

- Cursor tracks eye gaze with <30ms latency
- After calibration, cursor accuracy within ~100px of actual gaze target across the full screen
- Blink-to-click works reliably with <5% false positive rate from natural blinks
- App uses <15% CPU on Apple Silicon during active tracking
- A user can navigate to and click a macOS menu bar item, dock icon, or desktop file using only their eyes

## Future Phases

- **Phase 2:** Face expressions (wink/smile/brow raise for actions + mode switching) + floating HUD overlay
- **Phase 3:** Hand tracking + gesture recognition (swipe/pinch/grab for OS actions + custom shortcuts)
- **Phase 4:** Air typing / virtual keyboard with predictive text
- **Phase 5:** Full settings UI, system preference pane, gesture editor, profiles, onboarding polish
