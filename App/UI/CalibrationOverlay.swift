import SwiftUI
import LucentCore

@MainActor
final class CalibrationSession: ObservableObject {
    @Published var currentTargetIndex = 0
    @Published var samplesCollected = 0
    @Published var progress: Double = 0
    @Published var isComplete = false
    @Published var targets: [GazePoint] = []

    private var engine: CalibrationEngine?
    private weak var pipeline: TrackingPipeline?

    let samplesNeeded = 60
    let totalTargets = 9

    func start(screenSize: CGSize, pipeline: TrackingPipeline) {
        self.pipeline = pipeline
        let eng = CalibrationEngine(
            screenWidth: Double(screenSize.width),
            screenHeight: Double(screenSize.height)
        )
        engine = eng
        targets = eng.calibrationTargets()
        currentTargetIndex = 0
        samplesCollected = 0
        isComplete = false
        progress = 0

        // Hook into the pipeline's raw-gaze stream.
        pipeline.onRawGaze = { [weak self] gaze in
            Task { @MainActor [weak self] in
                self?.addGazeSample(gaze)
            }
        }
    }

    func stop() {
        pipeline?.onRawGaze = nil
        pipeline = nil
    }

    private func addGazeSample(_ gaze: GazePoint) {
        guard let engine = engine,
              currentTargetIndex < totalTargets,
              !isComplete else { return }

        engine.addSample(rawGaze: gaze, targetIndex: currentTargetIndex)
        samplesCollected += 1
        progress = Double(samplesCollected) / Double(samplesNeeded)

        if samplesCollected >= samplesNeeded {
            engine.advanceTarget()
            currentTargetIndex += 1
            samplesCollected = 0
            progress = 0

            if currentTargetIndex >= totalTargets {
                if let profile = engine.buildProfile(
                    cameraID: pipeline?.cameraDeviceID ?? "unknown"
                ) {
                    pipeline?.setCalibrationProfile(profile)
                }
                isComplete = true
                stop()
            }
        }
    }
}

struct CalibrationOverlay: View {
    @ObservedObject var appState: AppState
    @StateObject private var session = CalibrationSession()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if session.isComplete {
                    completionView
                } else if !session.targets.isEmpty && session.currentTargetIndex < session.targets.count {
                    targetDot(in: geo)
                    instructionText
                    statusOverlay
                } else {
                    startingView
                }
            }
            .onAppear { session.start(screenSize: geo.size, pipeline: appState.pipeline) }
            .onDisappear { session.stop() }
        }
    }

    private var startingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Preparing calibration...")
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func targetDot(in geo: GeometryProxy) -> some View {
        let target = session.targets[session.currentTargetIndex]
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)
                .frame(width: 40, height: 40)
            Circle()
                .trim(from: 0, to: session.progress)
                .stroke(Color.blue, lineWidth: 3)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
        }
        .position(x: target.x, y: target.y)
        .animation(.easeInOut(duration: 0.3), value: session.currentTargetIndex)
    }

    private var instructionText: some View {
        VStack {
            Spacer()
            Text("Look at the dot — \(session.currentTargetIndex + 1) of \(session.totalTargets)")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .padding(.bottom, 40)
        }
    }

    private var statusOverlay: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Face confidence: \(Int(appState.pipeline.faceConfidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Samples: \(session.samplesCollected) / \(session.samplesNeeded)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Frames received: \(appState.pipeline.frameCount)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    if let error = appState.pipeline.trackingError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    if !appState.pipeline.isEnabled {
                        Text("Tracking is OFF — enable Eye Tracking in the menu bar")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(16)
                Spacer()
            }
            Spacer()
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Calibration Complete")
                .font(.title)
                .foregroundColor(.white)
            Text("Eye tracking is now active")
                .foregroundColor(.white.opacity(0.7))
            Button("Done") {
                appState.showCalibration = false
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }
}
