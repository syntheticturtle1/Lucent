import Foundation

/// A 2D point representing gaze position.
/// In "raw" space these are normalized camera coords (0..1).
/// In "screen" space these are pixel coords.
public struct GazePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = GazePoint(x: 0, y: 0)

    public func distance(to other: GazePoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
