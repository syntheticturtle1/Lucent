import Foundation
import CoreGraphics

// MARK: - Key Press Sink Protocol

/// Protocol for posting key presses, allowing mock injection in tests.
public protocol KeyPressSink: AnyObject, Sendable {
    func pressKey(keyCode: UInt16, modifiers: CGEventFlags)
}

extension InputController: KeyPressSink {}

// MARK: - TypingSession

/// Manages the text buffer during keyboard mode.
/// Receives resolved key taps, handles special actions, and posts keystrokes to the OS.
public final class TypingSession: @unchecked Sendable {

    public private(set) var buffer: String = ""
    public private(set) var currentWord: String = ""
    public private(set) var isActive: Bool = false

    private let sink: KeyPressSink
    private let predictionEngine: PredictionEngine

    /// Production init with real InputController.
    public init(inputController: InputController, predictionEngine: PredictionEngine) {
        self.sink = inputController
        self.predictionEngine = predictionEngine
    }

    /// Flexible init with any KeyPressSink (enables testing with mocks).
    public init(sink: KeyPressSink, predictionEngine: PredictionEngine) {
        self.sink = sink
        self.predictionEngine = predictionEngine
    }

    public func start() {
        isActive = true
        buffer = ""
        currentWord = ""
    }

    public func stop() {
        isActive = false
    }

    public func reset() {
        buffer = ""
        currentWord = ""
        isActive = false
    }

    // MARK: - Typing Actions

    /// Type a single character from a key tap.
    public func typeCharacter(_ key: KeyDefinition) {
        guard isActive else { return }
        let char = key.label.lowercased()
        currentWord.append(char)
        postKey(keyCode: key.keyCode)
    }

    /// Delete the last character.
    public func backspace() {
        guard isActive else { return }
        if !currentWord.isEmpty {
            currentWord.removeLast()
            postKey(keyCode: 0x33)  // Delete key
        } else if !buffer.isEmpty {
            buffer.removeLast()
            postKey(keyCode: 0x33)
        }
    }

    /// Insert a space, completing the current word.
    public func space() {
        guard isActive else { return }
        buffer += currentWord + " "
        currentWord = ""
        postKey(keyCode: 0x31)  // Space key
    }

    /// Insert a newline / return.
    public func enter() {
        guard isActive else { return }
        buffer += currentWord + "\n"
        currentWord = ""
        postKey(keyCode: 0x24)  // Return key
    }

    /// Accept a predicted word, replacing the current partial word.
    public func acceptPrediction(_ word: String) {
        guard isActive else { return }

        // Erase the current partial word
        for _ in 0..<currentWord.count {
            postKey(keyCode: 0x33)  // Backspace
        }

        // Type the full predicted word
        for char in word {
            if let code = VirtualKeyboard.keyCode(for: char) {
                postKey(keyCode: code)
            }
        }

        // Add a space after the word
        postKey(keyCode: 0x31)

        // Update buffer
        buffer += word + " "
        currentWord = ""
    }

    /// Get current word predictions.
    public func currentPredictions() -> [String] {
        return predictionEngine.predict(prefix: currentWord)
    }

    // MARK: - Private

    private func postKey(keyCode: UInt16, modifiers: CGEventFlags = []) {
        sink.pressKey(keyCode: keyCode, modifiers: modifiers)
    }
}
