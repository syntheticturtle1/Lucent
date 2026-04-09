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

    // Keyboard mode state
    @Published public var keyboardModeActive: Bool = false
    @Published public var hoveredKey: KeyDefinition? = nil
    @Published public var currentTypedWord: String = ""
    @Published public var predictions: [String] = []
    @Published public var selectedPredictionIndex: Int? = nil

    private var isDragging: Bool = false
    private var isPointActive: Bool = false

    private let cameraManager = CameraManager()
    private let frameProcessor: FrameProcessor
    let blinkDetector = BlinkDetector()
    private(set) var cursorSmoother: CursorSmoother
    private let inputController = InputController()
    private let modeManager = InputModeManager()
    let headTiltProcessor = HeadTiltProcessor()
    private var calibrationProfile: CalibrationProfile?

    // Keyboard mode components
    private let tapDetector = TapDetector()
    private let keyResolver = KeyResolver()
    private let predictionEngine = PredictionEngine()
    private lazy var typingSession: TypingSession = {
        TypingSession(inputController: inputController, predictionEngine: predictionEngine)
    }()

    private var faceLostTime: Double?
    private let faceLostTimeout: Double = 0.5
    private var lowConfidenceCount = 0

    public var cameraDeviceID: String { cameraManager.currentDeviceID ?? "unknown" }

    /// Screen-space frame of the keyboard overlay, set by the UI layer.
    public var keyboardFrame: CGRect = CGRect(x: 0, y: 0, width: 600, height: 200)

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
        exitKeyboardMode()
    }

    public func toggle() throws { if isEnabled { stop() } else { try start() } }

    public func setCalibrationProfile(_ profile: CalibrationProfile) {
        self.calibrationProfile = profile
        try? profile.save()
        if isEnabled { trackingState = .tracking }
    }

    /// Apply all settings from a UserProfile to every pipeline component.
    public func applySettings(from settingsManager: SettingsManager) {
        settingsManager.apply(to: blinkDetector)
        settingsManager.apply(to: frameProcessor.expressionDetector)
        settingsManager.apply(to: frameProcessor.gestureRecognizer)
        settingsManager.apply(to: tapDetector)
        settingsManager.apply(to: headTiltProcessor)
        cursorSmoother = settingsManager.makeCursorSmoother()
        handGesturesEnabled = settingsManager.currentProfile.handGesturesEnabled
    }

    // MARK: - Keyboard Mode

    public func toggleKeyboardMode() {
        let events = modeManager.toggleKeyboardMode()
        currentMode = modeManager.currentMode
        for event in events {
            handleModeEvent(event)
        }
    }

    private func enterKeyboardMode() {
        keyboardModeActive = true
        typingSession.start()
        tapDetector.reset()
        hoveredKey = nil
        currentTypedWord = ""
        predictions = []
        selectedPredictionIndex = nil
    }

    private func exitKeyboardMode() {
        keyboardModeActive = false
        typingSession.stop()
        tapDetector.reset()
        hoveredKey = nil
        currentTypedWord = ""
        predictions = []
        selectedPredictionIndex = nil
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

        switch currentMode {
        case .normal, .commandPalette:
            blinkDetector.isEnabled = true
            headTiltProcessor.isEnabled = (currentMode == .normal)
            handleNormalTracking(result, profile: profile)
        case .scroll:
            blinkDetector.isEnabled = false
            headTiltProcessor.isEnabled = false
            handleScrollMode(result, profile: profile)
        case .dictation:
            blinkDetector.isEnabled = false
            headTiltProcessor.isEnabled = false
            handleWinkClicks(result)
        case .keyboard:
            blinkDetector.isEnabled = true  // Needed for prediction selection
            headTiltProcessor.isEnabled = false
            handleKeyboardMode(result, profile: profile)
        }

        // Process hand gestures only when NOT in keyboard mode
        if currentMode != .keyboard {
            handleGestureEvents(result.gestures, cursorPosition: currentCursorPosition)
        }
    }

    // MARK: - Keyboard Mode Frame Handling

    private func handleKeyboardMode(_ result: FrameProcessor.FrameResult, profile: CalibrationProfile) {
        // Eye tracking continues for cursor (prediction bar selection)
        let screenPoint = profile.mapToScreen(result.rawGaze)
        let smoothed = cursorSmoother.smooth(screenPoint)
        currentCursorPosition = smoothed
        inputController.moveCursor(to: smoothed)

        // Update prediction bar selection based on gaze position
        updatePredictionSelection(cursorPosition: smoothed)

        // Process hand data for typing
        guard let handData = result.hands.first else {
            hoveredKey = nil
            return
        }

        // Check for space gesture: thumb extended, all others curled
        if handData.fingerStates[.thumb] == .extended &&
           handData.fingerStates[.index] == .curled &&
           handData.fingerStates[.middle] == .curled &&
           handData.fingerStates[.ring] == .curled &&
           handData.fingerStates[.little] == .curled {
            typingSession.space()
            currentTypedWord = typingSession.currentWord
            predictions = typingSession.currentPredictions()
            return
        }

        // Check for backspace: reuse swipe-left gesture detection
        for gesture in result.gestures {
            if gesture.type == .swipeLeft && gesture.state == .discrete {
                typingSession.backspace()
                currentTypedWord = typingSession.currentWord
                predictions = typingSession.currentPredictions()
                return
            }
            // Fist gesture = enter
            if gesture.type == .fist && gesture.state == .began {
                typingSession.enter()
                currentTypedWord = typingSession.currentWord
                predictions = typingSession.currentPredictions()
                return
            }
        }

        // Update hovered key from fingertip position
        if let indexTip = handData.landmarks[.indexTip] {
            let screenPos = CGPoint(
                x: Double(indexTip.x) * profile.screenWidth,
                y: Double(indexTip.y) * profile.screenHeight
            )
            hoveredKey = keyResolver.resolve(
                fingertipScreenPosition: screenPos,
                keyboardFrame: keyboardFrame
            )
        }

        // Run tap detection
        if let tapEvent = tapDetector.update(handData: handData) {
            let screenPos = CGPoint(
                x: Double(tapEvent.fingertipPosition.x) * profile.screenWidth,
                y: Double(tapEvent.fingertipPosition.y) * profile.screenHeight
            )
            if let key = keyResolver.resolve(fingertipScreenPosition: screenPos, keyboardFrame: keyboardFrame) {
                if key.label != "space" {
                    typingSession.typeCharacter(key)
                    currentTypedWord = typingSession.currentWord
                    predictions = typingSession.currentPredictions()
                }
            }
        }

        // Handle blink for prediction acceptance
        let avgEAR = (result.leftEAR + result.rightEAR) / 2.0
        let clickEvents = blinkDetector.update(ear: avgEAR, timestamp: result.timestamp)
        for event in clickEvents {
            switch event {
            case .leftClick:
                if let idx = selectedPredictionIndex, idx < predictions.count {
                    typingSession.acceptPrediction(predictions[idx])
                    currentTypedWord = typingSession.currentWord
                    predictions = typingSession.currentPredictions()
                    selectedPredictionIndex = nil
                }
            default:
                break
            }
        }

        // Wink actions still pass through
        handleWinkClicks(result)
    }

    private func updatePredictionSelection(cursorPosition: GazePoint) {
        guard !predictions.isEmpty else {
            selectedPredictionIndex = nil
            return
        }

        // Prediction bar is at the top of the keyboard panel
        // Each prediction item spans 1/predictions.count of the width
        let barX = keyboardFrame.origin.x
        let barY = keyboardFrame.origin.y + keyboardFrame.height  // Above the keyboard
        let barWidth = keyboardFrame.width
        let barHeight: CGFloat = 40

        let cursorX = CGFloat(cursorPosition.x)
        let cursorY = CGFloat(cursorPosition.y)

        // Check if cursor is within prediction bar bounds
        if cursorX >= barX && cursorX <= barX + barWidth &&
           cursorY >= barY && cursorY <= barY + barHeight {
            let relativeX = (cursorX - barX) / barWidth
            let idx = Int(relativeX * CGFloat(predictions.count))
            selectedPredictionIndex = min(idx, predictions.count - 1)
        } else {
            selectedPredictionIndex = nil
        }
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
            case .keyboard: enterKeyboardMode()
            case .normal:
                if keyboardModeActive { exitKeyboardMode() }
            case .scroll: break
            }
        case .actionTriggered: break
        case .keyboardAction: break
        }
    }

    private func handleFaceLost(at time: Double) {
        if faceLostTime == nil { faceLostTime = time }
        if let lost = faceLostTime, time - lost > faceLostTimeout {
            trackingState = .paused(reason: .faceLost)
            let events = modeManager.handleFaceLost()
            if !events.isEmpty {
                currentMode = .normal
                if keyboardModeActive { exitKeyboardMode() }
            }
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

        if gestures.allSatisfy({ $0.state == .discrete || $0.state == .ended }) {
            activeGesture = nil
        }
    }
}
