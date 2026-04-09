import Testing
import CoreGraphics
@testable import LucentCore

// MARK: - Mock InputController for capturing key presses

/// Captures pressKey calls without posting real CGEvents.
final class MockInputController: KeyPressSink, @unchecked Sendable {
    var pressedKeys: [(keyCode: UInt16, modifiers: CGEventFlags)] = []

    func pressKey(keyCode: UInt16, modifiers: CGEventFlags = []) {
        pressedKeys.append((keyCode: keyCode, modifiers: modifiers))
    }

    func reset() {
        pressedKeys = []
    }
}

// MARK: - Tests

@Test func typeCharacterAppendsToCurrentWord() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [("hello", 100)])
    let session = TypingSession(sink: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)

    #expect(session.currentWord == "h")
    #expect(mockInput.pressedKeys.count == 1)
    #expect(mockInput.pressedKeys[0].keyCode == 0x04)
}

@Test func typeMultipleCharacters() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(sink: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    let keyI = KeyDefinition(label: "I", keyCode: 0x22, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.typeCharacter(keyI)

    #expect(session.currentWord == "hi")
    #expect(mockInput.pressedKeys.count == 2)
}

@Test func backspaceRemovesLastCharacter() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(sink: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.backspace()

    #expect(session.currentWord == "")
    #expect(mockInput.pressedKeys.last?.keyCode == 0x33)
}

@Test func backspaceOnEmptyWordDoesNothing() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(sink: mockInput, predictionEngine: engine)
    session.start()

    session.backspace()
    #expect(session.currentWord == "")
    #expect(session.buffer == "")
}

@Test func spaceCompletesWord() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(sink: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    let keyI = KeyDefinition(label: "I", keyCode: 0x22, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.typeCharacter(keyI)
    session.space()

    #expect(session.currentWord == "")
    #expect(session.buffer == "hi ")
    #expect(mockInput.pressedKeys.last?.keyCode == 0x31)
}

@Test func enterPostsReturnKey() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(sink: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.enter()

    #expect(session.currentWord == "")
    #expect(session.buffer.contains("\n"))
    #expect(mockInput.pressedKeys.last?.keyCode == 0x24)
}

@Test func acceptPredictionReplacesCurrentWord() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [("hello", 100)])
    let session = TypingSession(sink: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    let keyE = KeyDefinition(label: "E", keyCode: 0x0E, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.typeCharacter(keyE)

    // currentWord is "he", accept "hello"
    mockInput.reset()
    session.acceptPrediction("hello")

    // Should have: 2 backspaces (erase "he") + 5 letter keys (h,e,l,l,o) + 1 space
    #expect(mockInput.pressedKeys.count == 8)
    // First 2 are backspace (0x33)
    #expect(mockInput.pressedKeys[0].keyCode == 0x33)
    #expect(mockInput.pressedKeys[1].keyCode == 0x33)
    // Last is space (0x31)
    #expect(mockInput.pressedKeys.last?.keyCode == 0x31)
    #expect(session.currentWord == "")
    #expect(session.buffer.hasSuffix("hello "))
}

@Test func currentPredictionsReflectsTypedWord() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [
        ("hello", 500), ("help", 400), ("hero", 300), ("world", 200),
    ])
    let session = TypingSession(sink: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    let keyE = KeyDefinition(label: "E", keyCode: 0x0E, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.typeCharacter(keyE)

    let predictions = session.currentPredictions()
    #expect(predictions.count == 3)
    #expect(predictions[0] == "hello")
    #expect(predictions[1] == "help")
    #expect(predictions[2] == "hero")
}

@Test func resetClearsEverything() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(sink: mockInput, predictionEngine: engine)
    session.start()

    let keyH = KeyDefinition(label: "H", keyCode: 0x04, position: .zero, size: CGSize(width: 0.1, height: 0.25), row: 0)
    session.typeCharacter(keyH)
    session.reset()

    #expect(session.currentWord == "")
    #expect(session.buffer == "")
    #expect(!session.isActive)
}

@Test func stopDeactivatesSession() {
    let mockInput = MockInputController()
    let engine = PredictionEngine(words: [])
    let session = TypingSession(sink: mockInput, predictionEngine: engine)
    session.start()
    #expect(session.isActive)
    session.stop()
    #expect(!session.isActive)
}
