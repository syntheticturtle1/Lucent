import Testing
@testable import LucentCore

private func makeManager() -> InputModeManager {
    let m = InputModeManager()
    m.expressionModeSwitchingEnabled = true
    return m
}

@Test func startsInNormalMode() {
    let manager = InputModeManager()
    #expect(manager.currentMode == .normal)
}

@Test func mouthOpenSwitchesToScroll() {
    let manager = makeManager()
    let events = manager.process(expressions: [
        DetectedExpression(type: .mouthOpen, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .scroll)
    #expect(events.contains(.modeChanged(from: .normal, to: .scroll)))
}

@Test func mouthCloseExitsScroll() {
    let manager = makeManager()
    _ = manager.process(expressions: [
        DetectedExpression(type: .mouthOpen, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .scroll)
    let events = manager.process(expressions: [])
    #expect(manager.currentMode == .normal)
    #expect(events.contains(.modeChanged(from: .scroll, to: .normal)))
}

@Test func smileTogglesDictation() {
    let manager = makeManager()
    let on = manager.process(expressions: [
        DetectedExpression(type: .smile, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .dictation)
    #expect(on.contains(.modeChanged(from: .normal, to: .dictation)))
    let off = manager.process(expressions: [
        DetectedExpression(type: .smile, confidence: 0.8, timestamp: 2.0)
    ])
    #expect(manager.currentMode == .normal)
    #expect(off.contains(.modeChanged(from: .dictation, to: .normal)))
}

@Test func browRaiseTogglesCommandPalette() {
    let manager = makeManager()
    let on = manager.process(expressions: [
        DetectedExpression(type: .browRaise, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .commandPalette)
    let off = manager.process(expressions: [
        DetectedExpression(type: .browRaise, confidence: 0.8, timestamp: 2.0)
    ])
    #expect(manager.currentMode == .normal)
}

@Test func winkLeftTriggersAction() {
    let manager = InputModeManager()
    let events = manager.process(expressions: [
        DetectedExpression(type: .winkLeft, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(events.contains(.actionTriggered(.winkLeft)))
    #expect(manager.currentMode == .normal)
}

@Test func winkRightTriggersAction() {
    let manager = InputModeManager()
    let events = manager.process(expressions: [
        DetectedExpression(type: .winkRight, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(events.contains(.actionTriggered(.winkRight)))
}

@Test func faceLostReturnsToNormal() {
    let manager = makeManager()
    _ = manager.process(expressions: [
        DetectedExpression(type: .mouthOpen, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .scroll)
    let events = manager.handleFaceLost()
    #expect(manager.currentMode == .normal)
    #expect(events.contains(.modeChanged(from: .scroll, to: .normal)))
}

@Test func faceLostFromNormalNoEvent() {
    let manager = InputModeManager()
    let events = manager.handleFaceLost()
    #expect(events.isEmpty)
}

@Test func expressionModeSwitchingDisabledByDefault() {
    let manager = InputModeManager()
    let events = manager.process(expressions: [
        DetectedExpression(type: .smile, confidence: 0.8, timestamp: 1.0)
    ])
    #expect(manager.currentMode == .normal, "Should not switch when disabled")
    #expect(!events.contains(.modeChanged(from: .normal, to: .dictation)))
}
