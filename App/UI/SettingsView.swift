import SwiftUI
import LucentCore

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralTab(appState: appState).tabItem { Label("General", systemImage: "gear") }
            TrackingTab().tabItem { Label("Tracking", systemImage: "eye") }
            CursorTab(pipeline: appState.pipeline).tabItem { Label("Cursor", systemImage: "cursorarrow.motionlines") }
            ClickTab(pipeline: appState.pipeline).tabItem { Label("Click", systemImage: "hand.tap") }
            CalibrationTab(appState: appState).tabItem { Label("Calibration", systemImage: "target") }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 360)
    }
}

private struct GeneralTab: View {
    @ObservedObject var appState: AppState
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { appState.launchAtLogin }, set: { appState.launchAtLogin = $0 }))
            Toggle("Pause when screen locks", isOn: .constant(true))
            Section("Keyboard Shortcut") {
                Text("Toggle tracking: ⌘⇧L").foregroundColor(.secondary)
            }
        }.formStyle(.grouped)
    }
}

private struct TrackingTab: View {
    var body: some View {
        Form {
            Section("Camera") {
                Picker("Camera", selection: .constant("default")) {
                    Text("Default Camera").tag("default")
                    ForEach(CameraManager.availableCameras, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
            }
            Section("Frame Rate") {
                Picker("Frame Rate", selection: .constant(30)) {
                    Text("15 fps").tag(15)
                    Text("30 fps").tag(30)
                }.pickerStyle(.segmented)
            }
        }.formStyle(.grouped)
    }
}

private struct CursorTab: View {
    @ObservedObject var pipeline: TrackingPipeline
    var body: some View {
        Form {
            Section("Smoothing") { Slider(value: .constant(0.5), in: 0...1) { Text("Smoothing Strength") } }
            Section("Dwell Zone") { Slider(value: .constant(30.0), in: 10...60) { Text("Dwell Radius (px)") } }
            Section("Speed") { Slider(value: .constant(1.0), in: 0.5...2.0) { Text("Cursor Speed") } }
        }.formStyle(.grouped)
    }
}

private struct ClickTab: View {
    @ObservedObject var pipeline: TrackingPipeline
    var body: some View {
        Form {
            Section("Blink Thresholds") {
                Slider(value: .constant(0.3), in: 0.1...0.5) { Text("Quick Blink Max (s)") }
                Slider(value: .constant(0.8), in: 0.4...1.5) { Text("Long Blink Max (s)") }
            }
            Section("Filter") { Slider(value: .constant(0.5), in: 0...1) { Text("Natural Blink Filter Sensitivity") } }
            Section("Feedback") { Toggle("Click Sound", isOn: .constant(true)) }
        }.formStyle(.grouped)
    }
}

private struct CalibrationTab: View {
    @ObservedObject var appState: AppState
    var body: some View {
        Form {
            Section {
                Button("Run Full Calibration (9-point)") { appState.showCalibration = true }
                Button("Quick Recalibration (3-point)") {}
                    .disabled(true)
                    .help("Quick recalibration will be enabled in a future update")
            }
        }.formStyle(.grouped)
    }
}
