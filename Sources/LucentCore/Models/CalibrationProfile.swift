import Foundation

/// Stores polynomial coefficients mapping raw gaze to screen coordinates.
/// x_screen = a[0] + a[1]*gx + a[2]*gy + a[3]*gx^2 + a[4]*gy^2 + a[5]*gx*gy
/// y_screen = b[0] + b[1]*gx + b[2]*gy + b[3]*gx^2 + b[4]*gy^2 + b[5]*gx*gy
public struct CalibrationProfile: Codable, Equatable, Sendable {
    public var xCoefficients: [Double]  // 6 coefficients for x mapping
    public var yCoefficients: [Double]  // 6 coefficients for y mapping
    public var cameraID: String
    public var timestamp: Date
    public var screenWidth: Double
    public var screenHeight: Double

    public init(
        xCoefficients: [Double],
        yCoefficients: [Double],
        cameraID: String,
        timestamp: Date = Date(),
        screenWidth: Double,
        screenHeight: Double
    ) {
        precondition(xCoefficients.count == 6, "Need exactly 6 x coefficients")
        precondition(yCoefficients.count == 6, "Need exactly 6 y coefficients")
        self.xCoefficients = xCoefficients
        self.yCoefficients = yCoefficients
        self.cameraID = cameraID
        self.timestamp = timestamp
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }

    /// Map a raw gaze point to a screen coordinate using the polynomial.
    public func mapToScreen(_ raw: GazePoint) -> GazePoint {
        let gx = raw.x
        let gy = raw.y
        let features = [1.0, gx, gy, gx * gx, gy * gy, gx * gy]

        let sx = zip(xCoefficients, features).reduce(0.0) { $0 + $1.0 * $1.1 }
        let sy = zip(yCoefficients, features).reduce(0.0) { $0 + $1.0 * $1.1 }

        return GazePoint(
            x: max(0, min(screenWidth, sx)),
            y: max(0, min(screenHeight, sy))
        )
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Lucent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("calibration.json")
    }

    public func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.fileURL)
    }

    public static func load() throws -> CalibrationProfile {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(CalibrationProfile.self, from: data)
    }

    public static func deleteOnDisk() throws {
        try FileManager.default.removeItem(at: fileURL)
    }
}
