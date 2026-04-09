import Foundation
import CoreGraphics

// MARK: - Configuration

public struct KeyResolverConfig: Sendable {
    public var fuzzyMargin: Double
    public var maxHitRadius: Double

    public init(
        fuzzyMargin: Double = 0.05,
        maxHitRadius: Double = 0.08
    ) {
        self.fuzzyMargin = fuzzyMargin
        self.maxHitRadius = maxHitRadius
    }

    public static let defaults = KeyResolverConfig()
}

// MARK: - KeyResolver

public final class KeyResolver: Sendable {

    public let keyboard: VirtualKeyboard
    public let config: KeyResolverConfig

    public init(keyboard: VirtualKeyboard = .qwerty, config: KeyResolverConfig = .defaults) {
        self.keyboard = keyboard
        self.config = config
    }

    /// Map a screen-space fingertip position to the nearest key on the virtual keyboard.
    /// Returns nil if the position is outside keyboard bounds (with fuzzy margin)
    /// or if the nearest key is farther than maxHitRadius.
    public func resolve(
        fingertipScreenPosition: CGPoint,
        keyboardFrame: CGRect
    ) -> KeyDefinition? {
        // Convert screen position to keyboard-local normalized coordinates
        let localX = (fingertipScreenPosition.x - keyboardFrame.origin.x) / keyboardFrame.width
        let localY = (fingertipScreenPosition.y - keyboardFrame.origin.y) / keyboardFrame.height

        // Bounds check with fuzzy margin
        guard localX >= -config.fuzzyMargin,
              localX <= 1.0 + config.fuzzyMargin,
              localY >= -config.fuzzyMargin,
              localY <= 1.0 + config.fuzzyMargin else {
            return nil
        }

        let localPoint = CGPoint(x: localX, y: localY)

        guard let (key, distance) = nearestKey(localPosition: localPoint) else {
            return nil
        }

        guard distance <= config.maxHitRadius else {
            return nil
        }

        return key
    }

    /// Find the nearest key to a keyboard-local normalized position.
    /// Returns the key and the Euclidean distance to its center.
    public func nearestKey(localPosition: CGPoint) -> (key: KeyDefinition, distance: Double)? {
        guard !keyboard.keys.isEmpty else { return nil }

        var bestKey: KeyDefinition?
        var bestDistance: Double = .greatestFiniteMagnitude

        for key in keyboard.keys {
            let center = key.center
            let dx = Double(localPosition.x - center.x)
            let dy = Double(localPosition.y - center.y)
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDistance {
                bestDistance = dist
                bestKey = key
            }
        }

        guard let key = bestKey else { return nil }
        return (key, bestDistance)
    }
}
