import Foundation
import AVFoundation
import LucentCore

@MainActor
public final class TrackingPipeline: ObservableObject {
    @Published public var trackingState: TrackingState = .idle
    @Published public var isEnabled = false
    @Published public var currentCursorPosition = GazePoint.zero

    private let cameraManager = CameraManager()
    private let frameProcessor: FrameProcessor
    private let blinkDetector = BlinkDetector()
    private let cursorSmoother: CursorSmoother
    private let inputController = InputController()
    private var calibrationProfile: CalibrationProfile?

    private var faceLostTime: Double?
    private let faceLostTimeout: Double = 0.5
    private var lowConfidenceCount = 0

    public var cameraDeviceID: String {
        cameraManager.currentDeviceID ?? "unknown"
    }

    public init() {
        let gazeEstimator = MockGazeEstimator()
        self.frameProcessor = FrameProcessor(gazeEstimator: gazeEstimator)
        self.cursorSmoother = CursorSmoother()
        self.calibrationProfile = try? CalibrationProfile.load()
    }

    public func start() throws {
        guard !isEnabled else { return }
        try cameraManager.start()
        cameraManager.delegate = self
        isEnabled = true
        trackingState = calibrationProfile != nil ? .tracking : .detecting
    }

    public func stop() {
        cameraManager.stop()
        isEnabled = false
        trackingState = .idle
    }

    public func toggle() throws {
        if isEnabled { stop() } else { try start() }
    }

    public func setCalibrationProfile(_ profile: CalibrationProfile) {
        self.calibrationProfile = profile
        try? profile.save()
        if isEnabled { trackingState = .tracking }
    }
}

extension TrackingPipeline: CameraManagerDelegate {
    nonisolated public func cameraManager(_ manager: CameraManager, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        let time = CMTimeGetSeconds(timestamp)
        guard let result = frameProcessor.process(pixelBuffer: pixelBuffer, timestamp: time) else {
            Task { @MainActor in handleFaceLost(at: time) }
            return
        }
        Task { @MainActor in handleFrame(result) }
    }

    nonisolated public func cameraManager(_ manager: CameraManager, didFailWithError error: Error) {
        Task { @MainActor in trackingState = .paused(reason: .cameraDisconnected) }
    }
}

extension TrackingPipeline {
    private func handleFrame(_ result: FrameProcessor.FrameResult) {
        faceLostTime = nil
        if result.confidence < 0.5 {
            lowConfidenceCount += 1
            if lowConfidenceCount > 30 { trackingState = .paused(reason: .poorLighting) }
        } else { lowConfidenceCount = 0 }

        guard let profile = calibrationProfile else {
            trackingState = .detecting
            return
        }
        trackingState = .tracking
        let screenPoint = profile.mapToScreen(result.rawGaze)
        let smoothed = cursorSmoother.smooth(screenPoint)
        currentCursorPosition = smoothed
        inputController.moveCursor(to: smoothed)

        let avgEAR = (result.leftEAR + result.rightEAR) / 2.0
        let clickEvents = blinkDetector.update(ear: avgEAR, timestamp: result.timestamp)
        for event in clickEvents {
            switch event {
            case .leftClick: inputController.leftClick(at: smoothed)
            case .rightClick: inputController.rightClick(at: smoothed)
            case .doubleClick: inputController.doubleClick(at: smoothed)
            }
        }
    }

    private func handleFaceLost(at time: Double) {
        if faceLostTime == nil { faceLostTime = time }
        if let lost = faceLostTime, time - lost > faceLostTimeout {
            trackingState = .paused(reason: .faceLost)
        }
    }
}
