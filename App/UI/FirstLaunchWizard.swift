import SwiftUI
import LucentCore

struct FirstLaunchWizard: View {
    @ObservedObject var appState: AppState
    @State private var step = 0

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(i <= step ? Color.blue : Color.gray.opacity(0.3)).frame(height: 4)
                }
            }.padding(.horizontal)
            Spacer()
            switch step {
            case 0: welcomeStep
            case 1: cameraStep
            case 2: accessibilityStep
            case 3: readyStep
            default: EmptyView()
            }
            Spacer()
        }
        .padding(32)
        .frame(width: 480, height: 400)
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.circle.fill").font(.system(size: 64)).foregroundColor(.blue)
            Text("Welcome to Lucent").font(.largeTitle.bold())
            Text("Control your Mac with your eyes. Let's set up a few permissions first.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("Get Started") { step = 1 }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var cameraStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 48)).foregroundColor(.blue)
            Text("Camera Access").font(.title.bold())
            Text("Lucent needs your camera to track eye movements. Video is processed locally and never leaves your Mac.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            if appState.permissions.cameraGranted {
                Label("Camera access granted", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                Button("Continue") { step = 2 }.buttonStyle(.borderedProminent)
            } else {
                Button("Grant Camera Access") {
                    Task { await appState.permissions.requestCamera(); if appState.permissions.cameraGranted { step = 2 } }
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "accessibility").font(.system(size: 48)).foregroundColor(.blue)
            Text("Accessibility Access").font(.title.bold())
            Text("Lucent needs Accessibility permissions to move your cursor. You'll need to enable it in System Settings.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            if appState.permissions.accessibilityGranted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                Button("Continue") { step = 3 }.buttonStyle(.borderedProminent)
            } else {
                Button("Open System Settings") { appState.permissions.requestAccessibility() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Check Again") {
                    appState.permissions.refresh()
                    if appState.permissions.accessibilityGranted { step = 3 }
                }
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundColor(.green)
            Text("You're All Set!").font(.largeTitle.bold())
            Text("Calibrate your eye tracking, then use ⌘⇧L to toggle tracking on and off.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("Start Calibration") {
                appState.completeOnboarding()
                appState.showCalibration = true
            }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}
