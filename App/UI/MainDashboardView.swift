import SwiftUI
import AVFoundation
import LucentCore

// MARK: - Main Dashboard

struct MainDashboardView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
            Divider()

            HStack(spacing: 0) {
                // Left: Camera preview
                cameraPreview
                    .frame(minWidth: 320, maxWidth: .infinity)

                Divider()

                // Right: Controls + Status
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        controlToggles
                        Divider()
                        statusDashboard
                        Divider()
                        quickSettings
                    }
                    .padding(16)
                }
                .frame(width: 280)
            }
        }
        .frame(minWidth: 660, minHeight: 480)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: "eye.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)
            Text("Lucent")
                .font(.title2.bold())
            Spacer()

            // Tracking status pill
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(statusColor.opacity(0.15)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Camera Preview

    private var cameraPreview: some View {
        ZStack {
            Color.black

            if appState.pipeline.isEnabled {
                // Live camera feed
                CameraPreviewRepresentable(appState: appState)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)

                // Overlay: face confidence + hand count
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if appState.pipeline.faceConfidence > 0 {
                                Label("Face: \(Int(appState.pipeline.faceConfidence * 100))%",
                                      systemImage: "face.smiling")
                                    .font(.caption2.bold())
                                    .foregroundColor(.green)
                            }
                            if appState.pipeline.handCount > 0 {
                                Label("Hands: \(appState.pipeline.handCount)",
                                      systemImage: "hand.raised.fill")
                                    .font(.caption2.bold())
                                    .foregroundColor(.cyan)
                            }
                            if let gesture = appState.pipeline.activeGesture {
                                Label(gesture.rawValue, systemImage: "sparkles")
                                    .font(.caption2.bold())
                                    .foregroundColor(.yellow)
                            }
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.6)))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(16)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    Text("Camera Off")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("Enable Eye Tracking or Hand Gestures to start")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
        }
        .background(Color.black)
    }

    // MARK: - Control Toggles

    private var controlToggles: some View {
        VStack(spacing: 10) {
            Text("Controls")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ToggleCard(
                icon: "eye.fill",
                title: "Eye Tracking",
                subtitle: "Head + eye cursor control",
                color: .blue,
                isOn: Binding(
                    get: { appState.pipeline.eyeTrackingEnabled },
                    set: { _ in appState.toggleTracking() }
                )
            )

            ToggleCard(
                icon: "hand.raised.fill",
                title: "Hand Gestures",
                subtitle: "Swipe, pinch, fist, point",
                color: .cyan,
                isOn: Binding(
                    get: { appState.handGesturesEnabled },
                    set: { _ in appState.toggleHandGestures() }
                )
            )

            ToggleCard(
                icon: "keyboard.fill",
                title: "Virtual Keyboard",
                subtitle: "Air typing with finger taps",
                color: .orange,
                isOn: Binding(
                    get: { appState.keyboardModeEnabled },
                    set: { appState.setKeyboardModeEnabled($0) }
                )
            )

            ToggleCard(
                icon: "square.grid.2x2",
                title: "HUD Overlay",
                subtitle: "Floating status pill on screen",
                color: .purple,
                isOn: Binding(
                    get: { appState.showHUD },
                    set: { appState.showHUD = $0 }
                )
            )
        }
    }

    // MARK: - Status Dashboard

    private var statusDashboard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)

            StatusRow(label: "Camera", value: appState.pipeline.isEnabled ? "Running" : "Off",
                      color: appState.pipeline.isEnabled ? .green : .gray)
            StatusRow(label: "Frames", value: "\(appState.pipeline.frameCount)",
                      color: .secondary)
            StatusRow(label: "Face", value: appState.pipeline.faceConfidence > 0
                      ? "\(Int(appState.pipeline.faceConfidence * 100))%"
                      : "Not detected",
                      color: appState.pipeline.faceConfidence > 0.5 ? .green : .orange)
            StatusRow(label: "Hands", value: "\(appState.pipeline.handCount) detected",
                      color: appState.pipeline.handCount > 0 ? .cyan : .secondary)
            StatusRow(label: "Mode", value: modeName,
                      color: .blue)
            StatusRow(label: "Cursor", value: "(\(Int(appState.pipeline.currentCursorPosition.x)), \(Int(appState.pipeline.currentCursorPosition.y)))",
                      color: .secondary)

            if let error = appState.lastTrackingError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Quick Settings

    private var quickSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Settings")
                .font(.headline)

            Button(action: { appState.openCalibrationWindow?() }) {
                Label("Run Calibration", systemImage: "target")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!appState.pipeline.isEnabled)

            Button(action: { appState.openSettingsWindow?() }) {
                Label("All Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcuts").font(.caption.bold()).foregroundColor(.secondary)
                Text("\u{2318}\u{21E7}L — Toggle Eye Tracking").font(.caption2).foregroundColor(.secondary)
                Text("\u{2318}\u{21E7}H — Toggle HUD").font(.caption2).foregroundColor(.secondary)
                Text("\u{2318}\u{21E7}K — Toggle Keyboard").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if appState.pipeline.isEnabled {
            return appState.pipeline.faceConfidence > 0.3 ? .green : .yellow
        }
        return .gray
    }

    private var statusText: String {
        if !appState.pipeline.isEnabled { return "Off" }
        if appState.pipeline.faceConfidence > 0.3 { return "Tracking" }
        return "Detecting"
    }

    private var modeName: String {
        switch appState.pipeline.currentMode {
        case .normal: return "Normal"
        case .scroll: return "Scroll"
        case .dictation: return "Dictation"
        case .commandPalette: return "Spotlight"
        case .keyboard: return "Keyboard"
        }
    }
}

// MARK: - Reusable Components

private struct ToggleCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isOn ? color : .gray)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? color.opacity(0.08) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isOn ? color.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1))
    }
}

private struct StatusRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundColor(color)
        }
    }
}

// MARK: - Camera Preview (NSViewRepresentable)

struct CameraPreviewRepresentable: NSViewRepresentable {
    @ObservedObject var appState: AppState

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView()
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        if appState.pipeline.isEnabled {
            nsView.attachSession(appState.pipeline.cameraManager.session)
        } else {
            nsView.detachSession()
        }
    }
}

class CameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }

    func attachSession(_ session: AVCaptureSession) {
        guard previewLayer == nil else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        // Mirror the preview to match the user's perspective
        layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        self.layer?.addSublayer(layer)
        previewLayer = layer
    }

    func detachSession() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }
}
