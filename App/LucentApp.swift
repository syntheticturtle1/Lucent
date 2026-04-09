import SwiftUI
import LucentCore

@main
struct LucentApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.pipeline.isEnabled ? "eye.fill" : "eye")
        }

        Window("Welcome to Lucent", id: "wizard") {
            FirstLaunchWizard(appState: appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Lucent Settings", id: "settings") {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 500, height: 400)

        Window("Calibration", id: "calibration") {
            CalibrationOverlay(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
