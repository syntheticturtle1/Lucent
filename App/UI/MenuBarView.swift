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
        switch appState.pipeline.currentMode { case .normal: "eye"; case .scroll: "scroll"; case .dictation: "mic"; case .commandPalette: "magnifyingglass" }
    }
    private var modeName: String {
        switch appState.pipeline.currentMode { case .normal: "Normal"; case .scroll: "Scroll Mode"; case .dictation: "Dictation"; case .commandPalette: "Command Palette" }
    }
}
