import AppKit
import SwiftUI
import Combine
import LucentCore

/// Manages all app windows and the HUD panel using AppKit primitives.
/// SwiftUI's `Window` scenes are hard to drive from state, so we skip them for
/// onboarding/settings/calibration and create NSWindows directly.
@MainActor
final class WindowCoordinator: NSObject {
    private let appState: AppState

    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var calibrationWindow: NSWindow?

    private var hudPanel: HUDPanel?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        super.init()
        observeHUDState()
    }

    // MARK: - Onboarding

    func showOnboardingIfNeeded() {
        guard !appState.hasCompletedOnboarding else { return }
        showOnboarding()
    }

    func showOnboarding() {
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: OnboardingView(appState: appState))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Lucent"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings

    func showSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(appState: appState))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Lucent Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 460))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Calibration

    func showCalibration() {
        if let existing = calibrationWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: CalibrationOverlay(appState: appState))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Calibration"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        calibrationWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - HUD

    private func observeHUDState() {
        // React to tracking state and HUD toggle changes.
        appState.pipeline.$isEnabled
            .sink { [weak self] _ in self?.updateHUD() }
            .store(in: &cancellables)

        appState.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateHUD() }
            }
            .store(in: &cancellables)

        // Initial update once the pipeline publishes its starting value.
        updateHUD()
    }

    private func updateHUD() {
        let shouldShow = appState.showHUD && appState.pipeline.isEnabled

        if shouldShow {
            if hudPanel == nil {
                createHUDPanel()
            }
            refreshHUDContent()
            if let screen = NSScreen.main {
                hudPanel?.positionAtBottomCenter(of: screen)
            }
            hudPanel?.orderFront(nil)
        } else {
            hudPanel?.orderOut(nil)
        }
    }

    private func createHUDPanel() {
        let hosting = NSHostingView(rootView: HUDHost(appState: appState))
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 60)
        let panel = HUDPanel(contentView: hosting)
        panel.setContentSize(hosting.fittingSize)
        hudPanel = panel
    }

    private func refreshHUDContent() {
        guard let panel = hudPanel, let hosting = panel.contentView as? NSHostingView<HUDHost> else { return }
        hosting.rootView = HUDHost(appState: appState)
        let fitting = hosting.fittingSize
        panel.setContentSize(NSSize(width: max(fitting.width, 120), height: max(fitting.height, 36)))
    }
}

extension WindowCoordinator: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == onboardingWindow { onboardingWindow = nil }
        if window == settingsWindow { settingsWindow = nil }
        if window == calibrationWindow { calibrationWindow = nil }
    }
}

/// SwiftUI wrapper that chooses between minimal and expanded HUD views.
struct HUDHost: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if appState.hudExpanded {
                HUDExpandedView(
                    mode: appState.pipeline.currentMode,
                    confidence: appState.pipeline.faceConfidence,
                    expressions: appState.pipeline.activeExpressions,
                    cursorPosition: appState.pipeline.currentCursorPosition,
                    handCount: appState.pipeline.handCount,
                    activeGesture: appState.pipeline.activeGesture,
                    handGesturesEnabled: appState.handGesturesEnabled
                )
            } else {
                HUDMinimalView(
                    mode: appState.pipeline.currentMode,
                    confidence: appState.pipeline.faceConfidence,
                    activeExpression: appState.pipeline.activeExpressions.first?.type,
                    activeGesture: appState.pipeline.activeGesture,
                    handDetected: appState.pipeline.handDetected
                )
            }
        }
    }
}
