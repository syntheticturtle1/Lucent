import SwiftUI
import AppKit
import LucentCore

@main
struct LucentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appDelegate.appState)
                .environmentObject(appDelegate.appState)
        } label: {
            Image(systemName: appDelegate.appState.pipeline.isEnabled ? "eye.fill" : "eye")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()
    private(set) lazy var coordinator = WindowCoordinator(appState: appState)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make sure the coordinator is alive and observing HUD state.
        _ = coordinator

        // Route menu bar button taps through the coordinator.
        appState.openSettingsWindow = { [weak self] in self?.coordinator.showSettings() }
        appState.openCalibrationWindow = { [weak self] in self?.coordinator.showCalibration() }
        appState.openOnboardingWindow = { [weak self] in self?.coordinator.showOnboarding() }
        appState.closeOnboardingWindow = { [weak self] in self?.coordinator.closeOnboarding() }
        appState.openDashboardWindow = { [weak self] in self?.coordinator.showDashboard() }

        // On first launch show onboarding, otherwise show dashboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if self?.appState.hasCompletedOnboarding == true {
                self?.coordinator.showDashboard()
            } else {
                self?.coordinator.showOnboardingIfNeeded()
            }
        }

        // Refresh timer: propagate pipeline state changes to menu bar UI.
        // Needed because pipeline is a nested ObservableObject.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.appState.refreshPipelineState() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app: keep running even if all windows are closed.
        false
    }
}
