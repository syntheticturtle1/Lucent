import Foundation
import CoreGraphics
import ApplicationServices

public final class InputController: @unchecked Sendable {
    private let eventSource: CGEventSource?

    public init() {
        self.eventSource = CGEventSource(stateID: .hidSystemState)
    }

    public static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    public static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public func moveCursor(to point: GazePoint) {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        CGWarpMouseCursorPosition(cgPoint)
        if let event = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: cgPoint, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }

    public func leftClick(at point: GazePoint) {
        postClick(at: point, downType: .leftMouseDown, upType: .leftMouseUp, button: .left)
    }

    public func rightClick(at point: GazePoint) {
        postClick(at: point, downType: .rightMouseDown, upType: .rightMouseUp, button: .right)
    }

    public func doubleClick(at point: GazePoint) {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        for _ in 0..<2 {
            if let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: cgPoint, mouseButton: .left),
               let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: cgPoint, mouseButton: .left) {
                down.setIntegerValueField(.mouseEventClickState, value: 2)
                up.setIntegerValueField(.mouseEventClickState, value: 2)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func postClick(at point: GazePoint, downType: CGEventType, upType: CGEventType, button: CGMouseButton) {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        if let down = CGEvent(mouseEventSource: eventSource, mouseType: downType, mouseCursorPosition: cgPoint, mouseButton: button),
           let up = CGEvent(mouseEventSource: eventSource, mouseType: upType, mouseCursorPosition: cgPoint, mouseButton: button) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Post scroll wheel events.
    public func scroll(deltaY: Int32, deltaX: Int32 = 0) {
        if let event = CGEvent(scrollWheelEvent2Source: eventSource,
                               units: .pixel,
                               wheelCount: 2,
                               wheel1: deltaY,
                               wheel2: deltaX,
                               wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
    }

    /// Simulate a key press with optional modifiers.
    public func pressKey(keyCode: UInt16, modifiers: CGEventFlags = []) {
        if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) {
            down.flags = modifiers
            up.flags = modifiers
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Simulate pressing Fn twice (for macOS dictation).
    public func triggerDictation() {
        pressKey(keyCode: 0x3F)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            pressKey(keyCode: 0x3F)
        }
    }

    /// Simulate Cmd+Space (for Spotlight).
    public func triggerSpotlight() {
        pressKey(keyCode: 0x31, modifiers: .maskCommand)
    }
}
