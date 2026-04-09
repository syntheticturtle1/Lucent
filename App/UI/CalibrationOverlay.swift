import SwiftUI
import LucentCore

struct CalibrationOverlay: View {
    @ObservedObject var appState: AppState
    @State private var engine: CalibrationEngine?
    @State private var currentTargetIndex = 0
    @State private var samplesCollected = 0
    @State private var isComplete = false
    @State private var targets: [GazePoint] = []
    @State private var progress: Double = 0

    private let samplesNeeded = 60
    private let totalTargets = 9

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if isComplete {
                    completionView
                } else if !targets.isEmpty && currentTargetIndex < targets.count {
                    targetDot(in: geo)
                    instructionText
                }
            }
            .onAppear { startCalibration(screenSize: geo.size) }
        }
    }

    private func targetDot(in geo: GeometryProxy) -> some View {
        let target = targets[currentTargetIndex]
        return ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 3).frame(width: 40, height: 40)
            Circle().trim(from: 0, to: progress).stroke(Color.blue, lineWidth: 3).frame(width: 40, height: 40).rotationEffect(.degrees(-90))
            Circle().fill(Color.white).frame(width: 12, height: 12)
        }
        .position(x: target.x, y: target.y)
        .animation(.easeInOut(duration: 0.3), value: currentTargetIndex)
    }

    private var instructionText: some View {
        VStack {
            Spacer()
            Text("Look at the dot — \(currentTargetIndex + 1) of \(totalTargets)")
                .font(.title3).foregroundColor(.white.opacity(0.7)).padding(.bottom, 40)
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundColor(.green)
            Text("Calibration Complete").font(.title).foregroundColor(.white)
            Text("Eye tracking is now active").foregroundColor(.white.opacity(0.7))
            Button("Done") { appState.showCalibration = false }
                .buttonStyle(.borderedProminent).padding(.top, 8)
        }
    }

    private func startCalibration(screenSize: CGSize) {
        let eng = CalibrationEngine(screenWidth: Double(screenSize.width), screenHeight: Double(screenSize.height))
        engine = eng
        targets = eng.calibrationTargets()
        currentTargetIndex = 0
        samplesCollected = 0
        isComplete = false
        progress = 0
    }

    func addGazeSample(_ gaze: GazePoint) {
        guard let engine = engine, currentTargetIndex < totalTargets else { return }
        engine.addSample(rawGaze: gaze, targetIndex: currentTargetIndex)
        samplesCollected += 1
        progress = Double(samplesCollected) / Double(samplesNeeded)
        if samplesCollected >= samplesNeeded {
            engine.advanceTarget()
            currentTargetIndex += 1
            samplesCollected = 0
            progress = 0
            if currentTargetIndex >= totalTargets {
                if let profile = engine.buildProfile(cameraID: appState.pipeline.cameraDeviceID) {
                    appState.pipeline.setCalibrationProfile(profile)
                }
                isComplete = true
            }
        }
    }
}
