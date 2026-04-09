import Foundation

public final class InputModeManager: @unchecked Sendable {
    public private(set) var currentMode: InputMode = .normal
    private var scrollHeld = false

    public init() {}

    /// Toggle keyboard mode on/off. Called from Cmd+Shift+K hotkey handler.
    public func toggleKeyboardMode() -> [ModeEvent] {
        if currentMode == .keyboard {
            let previous = currentMode
            currentMode = .normal
            return [.modeChanged(from: previous, to: .normal)]
        } else if currentMode == .normal {
            let previous = currentMode
            currentMode = .keyboard
            return [.modeChanged(from: previous, to: .keyboard)]
        }
        // Can only enter keyboard mode from normal mode
        return []
    }

    public func process(expressions: [DetectedExpression]) -> [ModeEvent] {
        var events: [ModeEvent] = []
        let types = Set(expressions.map(\.type))

        // In keyboard mode, suppress expression-based mode changes
        // but still allow wink actions to pass through
        if currentMode == .keyboard {
            for expression in expressions {
                switch expression.type {
                case .winkLeft, .winkRight:
                    events.append(.actionTriggered(expression.type))
                default:
                    break  // Suppress scroll, dictation, command palette triggers
                }
            }
            return events
        }

        // Scroll: hold-to-activate, release to deactivate
        if currentMode == .scroll && !types.contains(.mouthOpen) {
            currentMode = .normal
            scrollHeld = false
            events.append(.modeChanged(from: .scroll, to: .normal))
        }

        for expression in expressions {
            switch expression.type {
            case .mouthOpen:
                if currentMode == .normal {
                    currentMode = .scroll
                    scrollHeld = true
                    events.append(.modeChanged(from: .normal, to: .scroll))
                }
            case .smile:
                if currentMode == .dictation {
                    currentMode = .normal
                    events.append(.modeChanged(from: .dictation, to: .normal))
                } else if currentMode == .normal {
                    currentMode = .dictation
                    events.append(.modeChanged(from: .normal, to: .dictation))
                }
            case .browRaise:
                if currentMode == .commandPalette {
                    currentMode = .normal
                    events.append(.modeChanged(from: .commandPalette, to: .normal))
                } else if currentMode == .normal {
                    currentMode = .commandPalette
                    events.append(.modeChanged(from: .normal, to: .commandPalette))
                }
            case .winkLeft, .winkRight:
                events.append(.actionTriggered(expression.type))
            }
        }
        return events
    }

    public func handleFaceLost() -> [ModeEvent] {
        if currentMode != .normal {
            let previous = currentMode
            currentMode = .normal
            scrollHeld = false
            return [.modeChanged(from: previous, to: .normal)]
        }
        return []
    }
}
