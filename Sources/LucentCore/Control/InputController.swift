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
}
