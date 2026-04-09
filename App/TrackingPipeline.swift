import Foundation
import AVFoundation
import LucentCore

@MainActor
public final class TrackingPipeline: ObservableObject {
    @Published public var trackingState: TrackingState = .idle
    @Published public var isEnabled = false
    @Published public var currentCursorPosition = GazePoint.zero
    @Published public var currentMode: InputMode = .normal
    @Published public var activeExpressions: [DetectedExpression] = []
    @Published public var faceConfidence: Float = 0
    @Published public var handDetected: Bool = false
    @Published public var activeGesture: GestureType? = nil
    @Published public var handGesturesEnabled: Bool = true
    @Published public var handCount: Int = 0

    private var isDragging: Bool = false
    private var isPointActive: Bool = false

    private let cameraManager = CameraManager()
    private let frameProcessor: FrameProcessor
    private let blinkDetector = BlinkDetector()
    private let cursorSmoother: CursorSmoother
    private let inputController = InputController()
    private let modeManager = InputModeManager()
    private let headTiltProcessor = HeadTiltProcessor()
    private var calibrationProfile: CalibrationProfile?

    private var faceLostTime: Double?
    private let faceLostTimeout: Double = 0.5
    private var lowConfidenceCount = 0

    public var cameraDeviceID: String { cameraManager.currentDeviceID ?? "unknown" }

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
        currentMode = .normal
    }

    public func toggle() throws { if isEnabled { stop() } else { try start() } }

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
        faceConfidence = result.confidence
        activeExpressions = result.expressions

        // Update hand tracking state
        handDetected = !result.hands.isEmpty
        handCount = result.hands.count

        if result.confidence < 0.5 {
            lowConfidenceCount += 1
            if lowConfidenceCount > 30 { trackingState = .paused(reason: .poorLighting) }
        } else { lowConfidenceCount = 0 }

        guard let profile = calibrationProfile else {
            trackingState = .detecting
            return
        }
        trackingState = .tracking

        let modeEvents = modeManager.process(expressions: result.expressions)
        currentMode = modeManager.currentMode

        for event in modeEvents {
            handleModeEvent(event)
        }

        blinkDetector.isEnabled = (currentMode == .normal || currentMode == .commandPalette)
        headTiltProcessor.isEnabled = (currentMode == .normal)

        switch currentMode {
        case .normal, .commandPalette:
            handleNormalTracking(result, profile: profile)
        case .scroll:
            handleScrollMode(result, profile: profile)
        case .dictation:
            handleWinkClicks(result)
        }

        // Process hand gestures (runs alongside all modes)
        handleGestureEvents(result.gestures, cursorPosition: currentCursorPosition)
    }

    private func handleNormalTracking(_ result: FrameProcessor.FrameResult, profile: CalibrationProfile) {
        // During point gesture, fingertip controls cursor — skip eye-gaze cursor
        if !isPointActive {
            let screenPoint = profile.mapToScreen(result.rawGaze)
            let smoothed = cursorSmoother.smooth(screenPoint)
            let tiltOffset = headTiltProcessor.process(rollDegrees: result.headRoll)
            let final = GazePoint(x: smoothed.x + tiltOffset.x, y: smoothed.y + tiltOffset.y)
            currentCursorPosition = final

            if isDragging {
                inputController.dragMove(to: final)
            } else {
                inputController.moveCursor(to: final)
            }
        }

        let avgEAR = (result.leftEAR + result.rightEAR) / 2.0
        let clickEvents = blinkDetector.update(ear: avgEAR, timestamp: result.timestamp)
        for event in clickEvents {
            switch event {
            case .leftClick: inputController.leftClick(at: currentCursorPosition)
            case .rightClick: inputController.rightClick(at: currentCursorPosition)
            case .doubleClick: inputController.doubleClick(at: currentCursorPosition)
            }
        }
        handleWinkClicks(result)
    }

    private func handleScrollMode(_ result: FrameProcessor.FrameResult, profile: CalibrationProfile) {
        let screenPoint = profile.mapToScreen(result.rawGaze)
        let vertCenter = profile.screenHeight / 2.0
        let vertDead = profile.screenHeight * 0.1
        let vertOffset = screenPoint.y - vertCenter
        var scrollY: Int32 = 0
        if abs(vertOffset) > vertDead {
            let speed = (abs(vertOffset) - vertDead) / (profile.screenHeight / 2.0)
            scrollY = Int32(speed * -10.0 * (vertOffset > 0 ? 1 : -1))
        }
        let horizCenter = profile.screenWidth / 2.0
        let horizDead = profile.screenWidth * 0.1
        let horizOffset = screenPoint.x - horizCenter
        var scrollX: Int32 = 0
        if abs(horizOffset) > horizDead {
            let speed = (abs(horizOffset) - horizDead) / (profile.screenWidth / 2.0)
            scrollX = Int32(speed * 10.0 * (horizOffset > 0 ? 1 : -1))
        }
        if scrollY != 0 || scrollX != 0 { inputController.scroll(deltaY: scrollY, deltaX: scrollX) }
        handleWinkClicks(result)
    }

    private func handleWinkClicks(_ result: FrameProcessor.FrameResult) {
        for expression in result.expressions {
            switch expression.type {
            case .winkLeft: inputController.rightClick(at: currentCursorPosition)
            case .winkRight: inputController.doubleClick(at: currentCursorPosition)
            default: break
            }
        }
    }

    private func handleModeEvent(_ event: ModeEvent) {
        switch event {
        case .modeChanged(_, let to):
            switch to {
            case .dictation: inputController.triggerDictation()
            case .commandPalette: inputController.triggerSpotlight()
            case .normal, .scroll: break
            }
        case .actionTriggered: break
        }
    }

    private func handleFaceLost(at time: Double) {
        if faceLostTime == nil { faceLostTime = time }
        if let lost = faceLostTime, time - lost > faceLostTimeout {
            trackingState = .paused(reason: .faceLost)
            let events = modeManager.handleFaceLost()
            if !events.isEmpty { currentMode = .normal }
        }
    }

    private func handleGestureEvents(_ gestures: [GestureEvent], cursorPosition: GazePoint) {
        guard handGesturesEnabled else { return }

        for gesture in gestures {
            activeGesture = gesture.type

            switch gesture.type {
            case .swipeLeft:
                guard gesture.state == .discrete else { continue }
                inputController.switchDesktop(direction: .left)

            case .swipeRight:
                guard gesture.state == .discrete else { continue }
                inputController.switchDesktop(direction: .right)

            case .swipeUp:
                guard gesture.state == .discrete else { continue }
                inputController.triggerMissionControl()

            case .swipeDown:
                guard gesture.state == .discrete else { continue }
                inputController.triggerExpose()

            case .pinch:
                switch gesture.state {
                case .changed(let distance):
                    // Smaller distance = fingers closing = zoom out
                    // Map distance changes to zoom direction
                    if distance < 0.015 {
                        inputController.zoom(direction: .zoomIn)
                    } else {
                        inputController.zoom(direction: .zoomOut)
                    }
                case .began, .ended, .discrete:
                    break
                }

            case .fist:
                switch gesture.state {
                case .began:
                    isDragging = true
                    inputController.startDrag(at: cursorPosition)
                case .ended:
                    isDragging = false
                    inputController.endDrag(at: cursorPosition)
                case .changed, .discrete:
                    break
                }

            case .point:
                switch gesture.state {
                case .began:
                    isPointActive = true
                case .changed(let encodedPosition):
                    // Decode fingertip position: x + y * 10000
                    let y = encodedPosition / 10000.0
                    let x = encodedPosition - (y.rounded(.down) * 10000.0)
                    if let profile = calibrationProfile {
                        let screenPoint = GazePoint(
                            x: x * profile.screenWidth,
                            y: y * profile.screenHeight
                        )
                        currentCursorPosition = screenPoint
                        if isDragging {
                            inputController.dragMove(to: screenPoint)
                        } else {
                            inputController.moveCursor(to: screenPoint)
                        }
                    }
                case .ended:
                    isPointActive = false
                case .discrete:
                    break
                }

            case .openPalm:
                guard gesture.state == .discrete else { continue }
                handGesturesEnabled.toggle()
                activeGesture = nil
            }
        }

        // Clear active gesture after processing one-shot events
        if gestures.allSatisfy({ $0.state == .discrete || $0.state == .ended }) {
            activeGesture = nil
        }
    }
}
