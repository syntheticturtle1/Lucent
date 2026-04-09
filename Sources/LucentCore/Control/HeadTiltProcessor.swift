import Foundation

public final class HeadTiltProcessor: @unchecked Sendable {
    public var deadZoneDegrees: Double = 3.0
    public var pixelsPerDegree: Double = 0.7
    public var isEnabled: Bool = true

    public init() {}

    public func process(rollDegrees: Double) -> GazePoint {
        guard isEnabled else { return .zero }
        let absRoll = abs(rollDegrees)
        guard absRoll > deadZoneDegrees else { return .zero }
        let effectiveRoll = absRoll - deadZoneDegrees
        let magnitude = effectiveRoll * pixelsPerDegree
        let direction = rollDegrees > 0 ? 1.0 : -1.0
        return GazePoint(x: magnitude * direction, y: 0)
    }
}
