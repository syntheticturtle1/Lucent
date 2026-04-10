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
            if let error = appState.lastTrackingError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
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
                set: { appState.showHUD = $0 }))
            Toggle("Hand Gestures", isOn: Binding(
                get: { appState.handGesturesEnabled },
                set: { _ in appState.toggleHandGestures() }))
            Toggle("Virtual Keyboard", isOn: Binding(
                get: { appState.keyboardModeEnabled },
                set: { appState.setKeyboardModeEnabled($0) }))
            Button("Quick Recalibrate") { appState.openCalibrationWindow?() }
                .disabled(!appState.pipeline.isEnabled)
            Divider()
            Button("Settings...") { appState.openSettingsWindow?() }
                .keyboardShortcut(",", modifiers: .command)
            Button("Show Onboarding") { appState.openOnboardingWindow?() }
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
