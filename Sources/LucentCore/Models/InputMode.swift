import Foundation

public enum InputMode: String, Codable, Sendable, CaseIterable {
    case normal
    case scroll
    case dictation
    case commandPalette
    case keyboard
}

public enum ExpressionType: String, Codable, Sendable, CaseIterable {
    case winkLeft
    case winkRight
    case smile
    case browRaise
    case mouthOpen
}

public struct DetectedExpression: Sendable, Equatable {
    public let type: ExpressionType
    public let confidence: Double
    public let timestamp: Double

    public init(type: ExpressionType, confidence: Double, timestamp: Double) {
        self.type = type
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

public struct ExpressionConfig: Codable, Sendable, Equatable {
    public var holdDuration: Double
    public var cooldown: Double
    public var thresholdMultiplier: Double

    public init(holdDuration: Double, cooldown: Double, thresholdMultiplier: Double) {
        self.holdDuration = holdDuration
        self.cooldown = cooldown
        self.thresholdMultiplier = thresholdMultiplier
    }

    public static let defaults: [ExpressionType: ExpressionConfig] = [
        .winkLeft: ExpressionConfig(holdDuration: 0.15, cooldown: 0.3, thresholdMultiplier: 1.0),
        .winkRight: ExpressionConfig(holdDuration: 0.15, cooldown: 0.3, thresholdMultiplier: 1.0),
        .smile: ExpressionConfig(holdDuration: 0.5, cooldown: 0.5, thresholdMultiplier: 1.4),
        .browRaise: ExpressionConfig(holdDuration: 0.3, cooldown: 0.5, thresholdMultiplier: 1.3),
        .mouthOpen: ExpressionConfig(holdDuration: 0.3, cooldown: 0.5, thresholdMultiplier: 2.0),
    ]
}

public enum ModeEvent: Equatable, Sendable {
    case modeChanged(from: InputMode, to: InputMode)
    case actionTriggered(ExpressionType)
    case keyboardAction(KeyboardActionType)
}

public enum KeyboardActionType: Equatable, Sendable {
    case keyTapped(character: String, keyCode: UInt16)
    case wordCompleted(word: String)
    case backspace
    case space
    case enter
}
