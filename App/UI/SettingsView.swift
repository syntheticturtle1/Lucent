import SwiftUI
import LucentCore

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralTab(appState: appState)
                .tabItem { Label("General", systemImage: "gear") }
            TrackingTab(appState: appState)
                .tabItem { Label("Tracking", systemImage: "eye") }
            CursorTab(appState: appState)
                .tabItem { Label("Cursor", systemImage: "cursorarrow.motionlines") }
            ClickTab(appState: appState)
                .tabItem { Label("Click", systemImage: "hand.tap") }
            ExpressionsTab(appState: appState)
                .tabItem { Label("Expressions", systemImage: "face.smiling") }
            GesturesTab(appState: appState)
                .tabItem { Label("Gestures", systemImage: "hand.raised") }
            KeyboardTab(appState: appState)
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
            CalibrationTab(appState: appState)
                .tabItem { Label("Calibration", systemImage: "target") }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }
}

// MARK: - Binding Helpers

extension AppState {
    func profileBinding<T>(_ keyPath: WritableKeyPath<UserProfile, T>) -> Binding<T> {
        Binding(
            get: { self.settingsManager.currentProfile[keyPath: keyPath] },
            set: { newValue in
                self.settingsManager.currentProfile[keyPath: keyPath] = newValue
                self.settingsManager.currentProfile.updatedAt = Date()
                self.settingsManager.saveCurrentProfile()
                self.pipeline.applySettings(from: self.settingsManager)
            }
        )
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.launchAtLogin = $0 }
                ))
                Toggle("Auto-start tracking on launch", isOn: appState.profileBinding(\.autoStartTracking))
                Toggle("Pause when screen locks", isOn: appState.profileBinding(\.pauseOnScreenLock))
            }

            Section("Keyboard Shortcuts") {
                Text("Toggle tracking: \u{2318}\u{21E7}L").foregroundColor(.secondary)
                Text("Toggle HUD: \u{2318}\u{21E7}H").foregroundColor(.secondary)
                Text("Toggle keyboard: \u{2318}\u{21E7}K").foregroundColor(.secondary)
            }

            Section("Profiles") {
                ProfilePickerView(appState: appState)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tracking Tab

private struct TrackingTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Camera") {
                Picker("Camera", selection: appState.profileBinding(\.selectedCameraID)) {
                    Text("Default Camera").tag(String?.none)
                    ForEach(CameraManager.availableCameras, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(Optional(device.uniqueID))
                    }
                }
            }

            Section("Status") {
                HStack {
                    Text("Face Confidence")
                    Spacer()
                    Text(String(format: "%.0f%%", appState.pipeline.faceConfidence * 100))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Tracking State")
                    Spacer()
                    Text(appState.pipeline.trackingState.displayName)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Hands Detected")
                    Spacer()
                    Text("\(appState.pipeline.handCount)")
                        .foregroundColor(.secondary)
                }
            }

            Section("HUD") {
                Toggle("Show HUD overlay", isOn: appState.profileBinding(\.showHUD))
                Toggle("HUD expanded by default", isOn: appState.profileBinding(\.hudExpanded))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Cursor Tab

private struct CursorTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Smoothing") {
                SliderRow(label: "Process Noise",
                          value: appState.profileBinding(\.cursorSmoothing),
                          range: 0.5...10.0, step: 0.5,
                          display: appState.settingsManager.currentProfile.cursorSmoothing, format: "%.1f")
                Text("Lower = smoother cursor, higher = more responsive")
                    .font(.caption).foregroundColor(.secondary)

                SliderRow(label: "Measurement Noise",
                          value: appState.profileBinding(\.cursorMeasurementNoise),
                          range: 1.0...20.0, step: 0.5,
                          display: appState.settingsManager.currentProfile.cursorMeasurementNoise, format: "%.1f")
            }

            Section("Dwell Zone") {
                SliderRow(label: "Dwell Radius (px)",
                          value: appState.profileBinding(\.dwellRadius),
                          range: 10...80, step: 1,
                          display: appState.settingsManager.currentProfile.dwellRadius, format: "%.0f")
                SliderRow(label: "Dwell Time (s)",
                          value: appState.profileBinding(\.dwellTime),
                          range: 0.05...1.0, step: 0.05,
                          display: appState.settingsManager.currentProfile.dwellTime, format: "%.2f")
            }

            Section("Speed") {
                SliderRow(label: "Cursor Speed",
                          value: appState.profileBinding(\.cursorSpeed),
                          range: 0.5...3.0, step: 0.1,
                          display: appState.settingsManager.currentProfile.cursorSpeed, format: "%.1fx")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Click Tab

private struct ClickTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Blink Detection") {
                SliderRow(label: "EAR Threshold",
                          value: appState.profileBinding(\.earThreshold),
                          range: 0.1...0.4, step: 0.01,
                          display: appState.settingsManager.currentProfile.earThreshold, format: "%.2f")
                SliderRow(label: "Quick Blink Max (s)",
                          value: appState.profileBinding(\.quickBlinkMaxDuration),
                          range: 0.1...0.5, step: 0.05,
                          display: appState.settingsManager.currentProfile.quickBlinkMaxDuration, format: "%.2f")
                SliderRow(label: "Long Blink Max (s)",
                          value: appState.profileBinding(\.longBlinkMaxDuration),
                          range: 0.4...1.5, step: 0.05,
                          display: appState.settingsManager.currentProfile.longBlinkMaxDuration, format: "%.2f")
            }

            Section("Timing") {
                SliderRow(label: "Double-Click Window (s)",
                          value: appState.profileBinding(\.doubleBlinkWindow),
                          range: 0.3...2.0, step: 0.1,
                          display: appState.settingsManager.currentProfile.doubleBlinkWindow, format: "%.1f")
                SliderRow(label: "Cooldown (s)",
                          value: appState.profileBinding(\.blinkCooldown),
                          range: 0.2...2.0, step: 0.05,
                          display: appState.settingsManager.currentProfile.blinkCooldown, format: "%.2f")
            }

            Section("Filter") {
                SliderRow(label: "Sharpness Threshold",
                          value: appState.profileBinding(\.blinkSharpness),
                          range: 0.02...0.2, step: 0.01,
                          display: appState.settingsManager.currentProfile.blinkSharpness, format: "%.2f")
                Text("Higher values require more intentional blinks")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Expressions Tab

private struct ExpressionsTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Wink Thresholds") {
                SliderRow(label: "Wink Closed EAR",
                          value: appState.profileBinding(\.winkClosedThreshold),
                          range: 0.05...0.3, step: 0.01,
                          display: appState.settingsManager.currentProfile.winkClosedThreshold, format: "%.2f")
                SliderRow(label: "Wink Open EAR",
                          value: appState.profileBinding(\.winkOpenThreshold),
                          range: 0.1...0.4, step: 0.01,
                          display: appState.settingsManager.currentProfile.winkOpenThreshold, format: "%.2f")
            }

            ForEach(ExpressionType.allCases, id: \.rawValue) { exprType in
                ExpressionConfigSection(appState: appState, expressionType: exprType)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ExpressionConfigSection: View {
    @ObservedObject var appState: AppState
    let expressionType: ExpressionType

    private var config: ExpressionConfig {
        appState.settingsManager.currentProfile.expressionConfig(for: expressionType)
    }

    var body: some View {
        Section(expressionType.displayName) {
            SliderRow(
                label: "Hold Duration (s)",
                value: Binding(
                    get: { config.holdDuration },
                    set: { newVal in
                        var c = config
                        c.holdDuration = newVal
                        appState.settingsManager.currentProfile.setExpressionConfig(c, for: expressionType)
                        appState.settingsManager.saveCurrentProfile()
                        appState.pipeline.applySettings(from: appState.settingsManager)
                    }
                ),
                range: 0.05...1.0, step: 0.05,
                display: config.holdDuration, format: "%.2f"
            )
            SliderRow(
                label: "Cooldown (s)",
                value: Binding(
                    get: { config.cooldown },
                    set: { newVal in
                        var c = config
                        c.cooldown = newVal
                        appState.settingsManager.currentProfile.setExpressionConfig(c, for: expressionType)
                        appState.settingsManager.saveCurrentProfile()
                        appState.pipeline.applySettings(from: appState.settingsManager)
                    }
                ),
                range: 0.1...2.0, step: 0.1,
                display: config.cooldown, format: "%.1f"
            )
            SliderRow(
                label: "Threshold Multiplier",
                value: Binding(
                    get: { config.thresholdMultiplier },
                    set: { newVal in
                        var c = config
                        c.thresholdMultiplier = newVal
                        appState.settingsManager.currentProfile.setExpressionConfig(c, for: expressionType)
                        appState.settingsManager.saveCurrentProfile()
                        appState.pipeline.applySettings(from: appState.settingsManager)
                    }
                ),
                range: 1.0...3.0, step: 0.1,
                display: config.thresholdMultiplier, format: "%.1f"
            )
        }
    }
}

// MARK: - Gestures Tab

private struct GesturesTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable Hand Gestures", isOn: appState.profileBinding(\.handGesturesEnabled))
            }

            Section("Swipe") {
                SliderRow(label: "Horizontal Displacement",
                          value: gestureBinding(\.swipeDisplacementX),
                          range: 0.1...0.6, step: 0.05,
                          display: appState.settingsManager.currentProfile.gestureConfig.swipeDisplacementX, format: "%.2f")
                SliderRow(label: "Vertical Displacement",
                          value: gestureBinding(\.swipeDisplacementY),
                          range: 0.1...0.5, step: 0.05,
                          display: appState.settingsManager.currentProfile.gestureConfig.swipeDisplacementY, format: "%.2f")
                SliderRow(label: "Swipe Window (s)",
                          value: gestureBinding(\.swipeWindowSeconds),
                          range: 0.2...1.0, step: 0.1,
                          display: appState.settingsManager.currentProfile.gestureConfig.swipeWindowSeconds, format: "%.1f")
                SliderRow(label: "Swipe Cooldown (s)",
                          value: gestureBinding(\.swipeCooldownSeconds),
                          range: 0.2...2.0, step: 0.1,
                          display: appState.settingsManager.currentProfile.gestureConfig.swipeCooldownSeconds, format: "%.1f")
            }

            Section("Pinch") {
                SliderRow(label: "Pinch Threshold",
                          value: gestureBinding(\.pinchThreshold),
                          range: 0.01...0.1, step: 0.005,
                          display: appState.settingsManager.currentProfile.gestureConfig.pinchThreshold, format: "%.3f")
            }

            Section("Hold Gestures") {
                SliderRow(label: "Fist Hold (s)",
                          value: gestureBinding(\.fistHoldDuration),
                          range: 0.1...1.0, step: 0.05,
                          display: appState.settingsManager.currentProfile.gestureConfig.fistHoldDuration, format: "%.2f")
                SliderRow(label: "Point Hold (s)",
                          value: gestureBinding(\.pointHoldDuration),
                          range: 0.1...1.0, step: 0.05,
                          display: appState.settingsManager.currentProfile.gestureConfig.pointHoldDuration, format: "%.2f")
                SliderRow(label: "Open Palm Hold (s)",
                          value: gestureBinding(\.openPalmHoldDuration),
                          range: 0.2...2.0, step: 0.1,
                          display: appState.settingsManager.currentProfile.gestureConfig.openPalmHoldDuration, format: "%.1f")
                SliderRow(label: "Open Palm Velocity",
                          value: gestureBinding(\.openPalmVelocityThreshold),
                          range: 0.005...0.05, step: 0.005,
                          display: appState.settingsManager.currentProfile.gestureConfig.openPalmVelocityThreshold, format: "%.3f")
            }
        }
        .formStyle(.grouped)
    }

    private func gestureBinding(_ keyPath: WritableKeyPath<GestureConfig, Double>) -> Binding<Double> {
        Binding(
            get: { appState.settingsManager.currentProfile.gestureConfig[keyPath: keyPath] },
            set: { newValue in
                appState.settingsManager.currentProfile.gestureConfig[keyPath: keyPath] = newValue
                appState.settingsManager.currentProfile.updatedAt = Date()
                appState.settingsManager.saveCurrentProfile()
                appState.pipeline.applySettings(from: appState.settingsManager)
            }
        )
    }
}

// MARK: - Keyboard Tab

private struct KeyboardTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Keyboard Mode") {
                Toggle("Enable Keyboard Mode", isOn: appState.profileBinding(\.keyboardEnabled))
                Text("When enabled, use \u{2318}\u{21E7}K to toggle the on-screen keyboard")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Layout") {
                SliderRow(label: "Key Size Multiplier",
                          value: appState.profileBinding(\.keySize),
                          range: 0.5...2.0, step: 0.1,
                          display: appState.settingsManager.currentProfile.keySize, format: "%.1fx")
            }

            Section("Predictions") {
                Toggle("Show Prediction Bar", isOn: appState.profileBinding(\.predictionBarEnabled))
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
            Section("Calibration") {
                Button("Run Full Calibration (9-point)") {
                    appState.openCalibrationWindow?()
                }
                .buttonStyle(.borderedProminent)
            }

            Section("Head Tilt") {
                SliderRow(label: "Dead Zone (degrees)",
                          value: appState.profileBinding(\.headTiltDeadZone),
                          range: 0...10, step: 0.5,
                          display: appState.settingsManager.currentProfile.headTiltDeadZone, format: "%.1f")
                SliderRow(label: "Pixels per Degree",
                          value: appState.profileBinding(\.headTiltPixelsPerDegree),
                          range: 0.1...3.0, step: 0.1,
                          display: appState.settingsManager.currentProfile.headTiltPixelsPerDegree, format: "%.1f")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Reusable Slider Row

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: Double
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, display))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

// MARK: - Helpers

extension ExpressionType {
    var displayName: String {
        switch self {
        case .winkLeft: return "Wink Left"
        case .winkRight: return "Wink Right"
        case .smile: return "Smile"
        case .browRaise: return "Brow Raise"
        case .mouthOpen: return "Mouth Open"
        }
    }
}

extension TrackingState {
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .detecting: return "Detecting"
        case .tracking: return "Tracking"
        case .calibrating: return "Calibrating"
        case .paused(let reason):
            switch reason {
            case .faceLost: return "Paused (face lost)"
            case .poorLighting: return "Paused (poor lighting)"
            case .cameraDisconnected: return "Paused (camera disconnected)"
            case .userPaused: return "Paused"
            }
        }
    }
}
