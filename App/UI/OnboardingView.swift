import SwiftUI
import LucentCore

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var step = 0
    @State private var profileName = "Default"
    @State private var selectedPreset: SensitivityPreset = .normal

    enum SensitivityPreset: String, CaseIterable {
        case beginner = "Beginner"
        case normal = "Normal"
        case advanced = "Advanced"

        var description: String {
            switch self {
            case .beginner: return "Higher smoothing, longer dwell times, more forgiving blink detection"
            case .normal: return "Balanced defaults for most users"
            case .advanced: return "Lower smoothing, faster response, tighter thresholds"
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal)

            Spacer()

            switch step {
            case 0: welcomeStep
            case 1: cameraStep
            case 2: accessibilityStep
            case 3: profileStep
            case 4: calibrationStep
            case 5: completeStep
            default: EmptyView()
            }

            Spacer()
        }
        .padding(32)
        .frame(width: 520, height: 480)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            Text("Welcome to Lucent")
                .font(.largeTitle.bold())
            Text("Control your Mac with your eyes, facial expressions, and hand gestures. Let's get you set up.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Get Started") { withAnimation { step = 1 } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    // MARK: - Step 2: Camera

    private var cameraStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            Text("Camera Access")
                .font(.title.bold())
            Text("Lucent needs your camera to track eye movements and hand gestures. Video is processed locally and never leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if appState.permissions.cameraGranted {
                Label("Camera access granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Button("Continue") { withAnimation { step = 2 } }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Grant Camera Access") {
                    Task {
                        await appState.permissions.requestCamera()
                        if appState.permissions.cameraGranted {
                            withAnimation { step = 2 }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Step 3: Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "accessibility")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            Text("Accessibility Access")
                .font(.title.bold())
            Text("Lucent needs Accessibility permissions to move your cursor. You'll need to enable it in System Settings.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if appState.permissions.accessibilityGranted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Button("Continue") { withAnimation { step = 3 } }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Open System Settings") {
                    appState.permissions.requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Check Again") {
                    appState.permissions.refresh()
                    if appState.permissions.accessibilityGranted {
                        withAnimation { step = 3 }
                    }
                }
            }
        }
    }

    // MARK: - Step 4: Profile Setup

    private var profileStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            Text("Create Your Profile")
                .font(.title.bold())
            Text("Set up a profile to store your preferences. You can create more profiles later.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Profile Name")
                    .font(.headline)
                TextField("Profile name", text: $profileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Text("Sensitivity Preset")
                    .font(.headline)
                    .padding(.top, 8)

                ForEach(SensitivityPreset.allCases, id: \.rawValue) { preset in
                    HStack {
                        Image(systemName: selectedPreset == preset ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(selectedPreset == preset ? .blue : .secondary)
                        VStack(alignment: .leading) {
                            Text(preset.rawValue).font(.body.bold())
                            Text(preset.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedPreset = preset }
                }
            }
            .frame(maxWidth: 350)

            Button("Continue") {
                applyProfilePreset()
                withAnimation { step = 4 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Step 5: Calibration

    private var calibrationStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            Text("Calibrate Eye Tracking")
                .font(.title.bold())
            Text("Calibration maps your eye position to your screen. Look at 9 dots that appear on screen and the system learns your gaze pattern.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Start Calibration") {
                appState.showCalibration = true
                withAnimation { step = 5 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Skip for now") {
                withAnimation { step = 5 }
            }
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Step 6: Complete

    private var completeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("You're All Set!")
                .font(.largeTitle.bold())

            VStack(alignment: .leading, spacing: 8) {
                Label("Toggle tracking: \u{2318}\u{21E7}L", systemImage: "keyboard")
                Label("Toggle HUD: \u{2318}\u{21E7}H", systemImage: "square.grid.2x2")
                Label("Toggle keyboard: \u{2318}\u{21E7}K", systemImage: "keyboard.badge.eye")
                Label("Open settings from the menu bar icon", systemImage: "gearshape")
            }
            .foregroundColor(.secondary)
            .padding()

            Button("Start Using Lucent") {
                appState.completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private func applyProfilePreset() {
        let base: UserProfile
        switch selectedPreset {
        case .beginner: base = .beginner()
        case .normal: base = .default
        case .advanced: base = .advanced()
        }

        var profile = base
        profile.id = appState.settingsManager.currentProfile.id
        profile.name = profileName.isEmpty ? "Default" : profileName
        profile.createdAt = appState.settingsManager.currentProfile.createdAt
        profile.updatedAt = Date()
        appState.settingsManager.currentProfile = profile
        appState.settingsManager.saveCurrentProfile()
        appState.pipeline.applySettings(from: appState.settingsManager)
    }
}
