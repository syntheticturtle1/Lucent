import Foundation
import CoreGraphics

/// Recognizes gestures from a stream of HandData + velocity.
/// Emits GestureEvents for swipes, pinch, fist, point, and open palm.
public final class GestureRecognizer: @unchecked Sendable {

    // MARK: - Configuration

    public var config: GestureConfig

    // MARK: - Swipe State

    /// Sliding window of (wristPosition, timestamp) for swipe detection.
    private var wristHistory: [(position: CGPoint, timestamp: Double)] = []
    /// Tracks whether all fingers were extended throughout the swipe window.
    private var allFingersExtendedHistory: [Bool] = []
    /// Timestamp of last swipe fired (for cooldown).
    private var lastSwipeTime: Double = -.infinity

    // MARK: - Continuous Gesture State

    private var fistStartTime: Double?
    private var fistActive: Bool = false

    private var pointStartTime: Double?
    private var pointActive: Bool = false

    private var pinchActive: Bool = false
    private var previousPinchDistance: Double?

    private var openPalmStartTime: Double?
    private var openPalmFired: Bool = false

    // MARK: - Init

    public init(config: GestureConfig = .defaults) {
        self.config = config
    }

    // MARK: - Reset

    public func reset() {
        wristHistory.removeAll()
        allFingersExtendedHistory.removeAll()
        lastSwipeTime = -.infinity
        fistStartTime = nil
        fistActive = false
        pointStartTime = nil
        pointActive = false
        pinchActive = false
        previousPinchDistance = nil
        openPalmStartTime = nil
        openPalmFired = false
    }

    // MARK: - Main Update

    /// Process one frame of hand data. Returns any gesture events detected.
    public func update(hand: HandData, velocity: CGPoint, timestamp: Double) -> [GestureEvent] {
        var events: [GestureEvent] = []

        // Detect gestures in priority order
        events += detectPinch(hand: hand, timestamp: timestamp)
        events += detectFist(hand: hand, timestamp: timestamp)
        events += detectPoint(hand: hand, timestamp: timestamp)
        events += detectOpenPalm(hand: hand, velocity: velocity, timestamp: timestamp)
        events += detectSwipe(hand: hand, velocity: velocity, timestamp: timestamp)

        return events
    }

    // MARK: - Hand Lost

    /// Call when no hand is detected. Ends any active continuous gestures.
    public func handleHandLost(timestamp: Double) -> [GestureEvent] {
        var events: [GestureEvent] = []

        if fistActive {
            events.append(GestureEvent(type: .fist, state: .ended, timestamp: timestamp))
            fistActive = false
            fistStartTime = nil
        }
        if pointActive {
            events.append(GestureEvent(type: .point, state: .ended, timestamp: timestamp))
            pointActive = false
            pointStartTime = nil
        }
        if pinchActive {
            events.append(GestureEvent(type: .pinch, state: .ended, timestamp: timestamp))
            pinchActive = false
            previousPinchDistance = nil
        }

        wristHistory.removeAll()
        allFingersExtendedHistory.removeAll()
        openPalmStartTime = nil
        openPalmFired = false

        return events
    }

    // MARK: - Swipe Detection

    private func detectSwipe(hand: HandData, velocity: CGPoint, timestamp: Double) -> [GestureEvent] {
        let allExtended = Finger.allCases.allSatisfy { hand.fingerStates[$0] == .extended }

        // Add to history
        wristHistory.append((position: hand.wristPosition, timestamp: timestamp))
        allFingersExtendedHistory.append(allExtended)

        // Trim history to the swipe window
        let windowStart = timestamp - config.swipeWindowSeconds
        while let first = wristHistory.first, first.timestamp < windowStart {
            wristHistory.removeFirst()
            allFingersExtendedHistory.removeFirst()
        }

        // Check cooldown
        guard timestamp - lastSwipeTime >= config.swipeCooldownSeconds else { return [] }

        // Need at least 2 samples
        guard wristHistory.count >= 2 else { return [] }

        // All fingers must have been extended throughout the window
        guard allFingersExtendedHistory.allSatisfy({ $0 }) else { return [] }

        // Compute total displacement
        let first = wristHistory.first!.position
        let last = wristHistory.last!.position
        let dx = Double(last.x - first.x)
        let dy = Double(last.y - first.y)

        var gestureType: GestureType?

        if dx > Double(config.swipeDisplacementX) {
            gestureType = .swipeRight
        } else if dx < -Double(config.swipeDisplacementX) {
            gestureType = .swipeLeft
        } else if dy < -Double(config.swipeDisplacementY) {
            gestureType = .swipeUp
        } else if dy > Double(config.swipeDisplacementY) {
            gestureType = .swipeDown
        }

        if let type = gestureType {
            lastSwipeTime = timestamp
            wristHistory.removeAll()
            allFingersExtendedHistory.removeAll()
            return [GestureEvent(type: type, state: .discrete, timestamp: timestamp)]
        }

        return []
    }

    // MARK: - Pinch Detection

    private func detectPinch(hand: HandData, timestamp: Double) -> [GestureEvent] {
        guard let thumbTip = hand.landmarks[.thumbTip],
              let indexTip = hand.landmarks[.indexTip] else {
            if pinchActive {
                pinchActive = false
                previousPinchDistance = nil
                return [GestureEvent(type: .pinch, state: .ended, timestamp: timestamp)]
            }
            return []
        }

        let distance = sqrt(
            pow(Double(thumbTip.x - indexTip.x), 2) +
            pow(Double(thumbTip.y - indexTip.y), 2)
        )

        // Check that middle, ring, little are extended (pinch pose)
        let middleExtended = hand.fingerStates[.middle] == .extended
        let ringExtended = hand.fingerStates[.ring] == .extended
        let littleExtended = hand.fingerStates[.little] == .extended
        let isPinchPose = distance < config.pinchThreshold && middleExtended && ringExtended && littleExtended

        if isPinchPose {
            if !pinchActive {
                pinchActive = true
                previousPinchDistance = distance
                return [GestureEvent(type: .pinch, state: .began, timestamp: timestamp)]
            } else {
                let event = GestureEvent(type: .pinch, state: .changed(value: distance), timestamp: timestamp)
                previousPinchDistance = distance
                return [event]
            }
        } else {
            if pinchActive {
                pinchActive = false
                previousPinchDistance = nil
                return [GestureEvent(type: .pinch, state: .ended, timestamp: timestamp)]
            }
        }

        return []
    }

    // MARK: - Fist Detection

    private func detectFist(hand: HandData, timestamp: Double) -> [GestureEvent] {
        let allCurled = Finger.allCases.allSatisfy { hand.fingerStates[$0] == .curled }

        if allCurled {
            if fistStartTime == nil {
                fistStartTime = timestamp
            }
            let held = timestamp - fistStartTime!

            if held >= config.fistHoldDuration && !fistActive {
                fistActive = true
                return [GestureEvent(type: .fist, state: .began, timestamp: timestamp)]
            }
        } else {
            if fistActive {
                fistActive = false
                fistStartTime = nil
                return [GestureEvent(type: .fist, state: .ended, timestamp: timestamp)]
            }
            fistStartTime = nil
        }

        return []
    }

    // MARK: - Point Detection

    private func detectPoint(hand: HandData, timestamp: Double) -> [GestureEvent] {
        let indexExtended = hand.fingerStates[.index] == .extended
        let othersCurled = [Finger.thumb, .middle, .ring, .little].allSatisfy {
            hand.fingerStates[$0] == .curled
        }
        let isPointing = indexExtended && othersCurled

        if isPointing {
            if pointStartTime == nil {
                pointStartTime = timestamp
            }
            let held = timestamp - pointStartTime!

            if held >= config.pointHoldDuration {
                if !pointActive {
                    pointActive = true
                    return [GestureEvent(type: .point, state: .began, timestamp: timestamp)]
                } else {
                    // Report fingertip position as changed value
                    let indexTip = hand.landmarks[.indexTip] ?? hand.wristPosition
                    let positionValue = Double(indexTip.x) + Double(indexTip.y) * 10000.0
                    return [GestureEvent(type: .point, state: .changed(value: positionValue), timestamp: timestamp)]
                }
            }
        } else {
            if pointActive {
                pointActive = false
                pointStartTime = nil
                return [GestureEvent(type: .point, state: .ended, timestamp: timestamp)]
            }
            pointStartTime = nil
        }

        return []
    }

    // MARK: - Open Palm Detection

    private func detectOpenPalm(hand: HandData, velocity: CGPoint, timestamp: Double) -> [GestureEvent] {
        let allExtended = Finger.allCases.allSatisfy { hand.fingerStates[$0] == .extended }
        let speed = sqrt(Double(velocity.x * velocity.x + velocity.y * velocity.y))
        let isStationary = speed < config.openPalmVelocityThreshold

        if allExtended && isStationary {
            if openPalmStartTime == nil {
                openPalmStartTime = timestamp
            }
            let held = timestamp - openPalmStartTime!

            if held >= config.openPalmHoldDuration && !openPalmFired {
                openPalmFired = true
                return [GestureEvent(type: .openPalm, state: .discrete, timestamp: timestamp)]
            }
        } else {
            openPalmStartTime = nil
            openPalmFired = false
        }

        return []
    }
}
