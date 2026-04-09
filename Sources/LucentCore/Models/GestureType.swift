import Foundation
import CoreGraphics

// MARK: - Hand Joint Topology

public enum HandJoint: String, CaseIterable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

// MARK: - Finger Classification

public enum Finger: String, CaseIterable, Sendable {
    case thumb, index, middle, ring, little
}

public enum FingerState: String, Sendable, Equatable {
    case extended
    case curled
}

public enum Chirality: String, Sendable, Equatable {
    case left
    case right
}

// MARK: - Hand Data (output of HandDetector)

public struct HandData: Sendable, Equatable {
    public let landmarks: [HandJoint: CGPoint]
    public let fingerStates: [Finger: FingerState]
    public let wristPosition: CGPoint
    public let chirality: Chirality
    public let confidence: Float
    public let timestamp: Double

    public init(
        landmarks: [HandJoint: CGPoint],
        fingerStates: [Finger: FingerState],
        wristPosition: CGPoint,
        chirality: Chirality,
        confidence: Float,
        timestamp: Double
    ) {
        self.landmarks = landmarks
        self.fingerStates = fingerStates
        self.wristPosition = wristPosition
        self.chirality = chirality
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

// MARK: - Movement

public enum SwipeDirection: String, Sendable, Equatable, CaseIterable {
    case left, right, up, down
}

public enum ZoomDirection: String, Sendable, Equatable {
    case zoomIn, zoomOut
}

// MARK: - Gesture Types

public enum GestureType: String, Codable, Sendable, CaseIterable, Equatable {
    case swipeLeft, swipeRight, swipeUp, swipeDown
    case pinch, fist, point, openPalm
}

public enum GestureState: Sendable, Equatable {
    case began
    case changed(value: Double)
    case ended
    case discrete
}

public struct GestureEvent: Sendable, Equatable {
    public let type: GestureType
    public let state: GestureState
    public let timestamp: Double

    public init(type: GestureType, state: GestureState, timestamp: Double) {
        self.type = type
        self.state = state
        self.timestamp = timestamp
    }
}

// MARK: - Gesture Configuration

public struct GestureConfig: Codable, Sendable, Equatable {
    public var swipeDisplacementX: Double
    public var swipeDisplacementY: Double
    public var swipeWindowSeconds: Double
    public var swipeCooldownSeconds: Double
    public var pinchThreshold: Double
    public var fistHoldDuration: Double
    public var pointHoldDuration: Double
    public var openPalmHoldDuration: Double
    public var openPalmVelocityThreshold: Double
    public var fingerExtendedAngle: Double
    public var thumbExtendedAngle: Double

    public init(
        swipeDisplacementX: Double = 0.30,
        swipeDisplacementY: Double = 0.25,
        swipeWindowSeconds: Double = 0.5,
        swipeCooldownSeconds: Double = 0.5,
        pinchThreshold: Double = 0.03,
        fistHoldDuration: Double = 0.3,
        pointHoldDuration: Double = 0.2,
        openPalmHoldDuration: Double = 0.5,
        openPalmVelocityThreshold: Double = 0.01,
        fingerExtendedAngle: Double = 150.0,
        thumbExtendedAngle: Double = 140.0
    ) {
        self.swipeDisplacementX = swipeDisplacementX
        self.swipeDisplacementY = swipeDisplacementY
        self.swipeWindowSeconds = swipeWindowSeconds
        self.swipeCooldownSeconds = swipeCooldownSeconds
        self.pinchThreshold = pinchThreshold
        self.fistHoldDuration = fistHoldDuration
        self.pointHoldDuration = pointHoldDuration
        self.openPalmHoldDuration = openPalmHoldDuration
        self.openPalmVelocityThreshold = openPalmVelocityThreshold
        self.fingerExtendedAngle = fingerExtendedAngle
        self.thumbExtendedAngle = thumbExtendedAngle
    }

    public static let defaults = GestureConfig()
}
