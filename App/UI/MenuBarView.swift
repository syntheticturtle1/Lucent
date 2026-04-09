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
            .padding(.bottom, 4)
            Divider()
            Toggle("Eye Tracking", isOn: Binding(
                get: { appState.pipeline.isEnabled },
                set: { _ in appState.toggleTracking() }
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
}
