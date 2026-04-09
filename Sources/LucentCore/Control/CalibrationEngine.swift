import Foundation
import Accelerate

/// Collects gaze samples during a 9-point calibration and fits a 2nd-degree
/// polynomial using LAPACK least squares (dgels_) to produce a CalibrationProfile.
public final class CalibrationEngine: @unchecked Sendable {

    // MARK: - Configuration

    public let screenWidth: Double
    public let screenHeight: Double

    /// Fraction of screen used as margin around the calibration grid.
    private let margin = 0.10

    // MARK: - State

    /// Samples collected per target index: [targetIndex: [GazePoint]]
    private var samplesPerTarget: [[GazePoint]]

    /// Index of the target currently being calibrated (0-based, 0..<9).
    public private(set) var currentTargetIndex: Int = 0

    private let targetCount = 9

    // MARK: - Init

    public init(screenWidth: Double, screenHeight: Double) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.samplesPerTarget = Array(repeating: [], count: targetCount)
    }

    // MARK: - Calibration targets

    /// Returns the 9 screen-space calibration target positions in reading order
    /// (TL, TC, TR, ML, MC, MR, BL, BC, BR) with a 10% margin.
    public func calibrationTargets() -> [GazePoint] {
        let xs = [margin, 0.5, 1.0 - margin].map { $0 * screenWidth }
        let ys = [margin, 0.5, 1.0 - margin].map { $0 * screenHeight }
        var targets: [GazePoint] = []
        for y in ys {
            for x in xs {
                targets.append(GazePoint(x: x, y: y))
            }
        }
        return targets
    }

    // MARK: - Sample collection

    /// Add a raw gaze sample for the given target index.
    public func addSample(rawGaze: GazePoint, targetIndex: Int) {
        guard targetIndex >= 0, targetIndex < targetCount else { return }
        samplesPerTarget[targetIndex].append(rawGaze)
    }

    /// Number of samples collected for a given target.
    public func sampleCount(for targetIndex: Int) -> Int {
        guard targetIndex >= 0, targetIndex < targetCount else { return 0 }
        return samplesPerTarget[targetIndex].count
    }

    /// Move to the next calibration target.
    public func advanceTarget() {
        if currentTargetIndex < targetCount - 1 {
            currentTargetIndex += 1
        }
    }

    /// Reset all collected samples and return to the first target.
    public func reset() {
        samplesPerTarget = Array(repeating: [], count: targetCount)
        currentTargetIndex = 0
    }

    // MARK: - Profile building

    /// Averages samples per target (after outlier rejection), then fits
    /// a polynomial using the resulting 9 point pairs.
    /// Returns nil if any target has no samples.
    public func buildProfile(cameraID: String) -> CalibrationProfile? {
        let targets = calibrationTargets()
        var gazePoints: [GazePoint] = []
        var screenPoints: [GazePoint] = []

        for (i, target) in targets.enumerated() {
            let raw = samplesPerTarget[i]
            guard !raw.isEmpty else { return nil }
            let cleaned = Self.rejectOutliers(raw)
            let samples = cleaned.isEmpty ? raw : cleaned
            let meanGaze = mean(samples)
            gazePoints.append(meanGaze)
            screenPoints.append(target)
        }

        return fit(gazePoints: gazePoints, screenPoints: screenPoints, cameraID: cameraID)
    }

    // MARK: - Polynomial fitting

    /// Fit a 2nd-degree bivariate polynomial using LAPACK dgels_ (least squares).
    ///
    /// Feature vector per point: [1, gx, gy, gx², gy², gx·gy]
    /// Separate fits for x and y screen coordinates.
    public func fit(
        gazePoints: [GazePoint],
        screenPoints: [GazePoint],
        cameraID: String
    ) -> CalibrationProfile {
        let n = gazePoints.count
        let nFeatures = 6

        // Build the feature matrix A (column-major for LAPACK/Fortran).
        // Shape: n rows × 6 cols  →  column-major array of length n*6.
        var A = [Double](repeating: 0.0, count: n * nFeatures)
        for row in 0..<n {
            let gx = gazePoints[row].x
            let gy = gazePoints[row].y
            let features: [Double] = [1.0, gx, gy, gx * gx, gy * gy, gx * gy]
            for col in 0..<nFeatures {
                // Column-major: element [row, col] → A[col * n + row]
                A[col * n + row] = features[col]
            }
        }

        // Build right-hand-side vectors (B).
        // dgels_ overwrites B with the solution; B must be max(n, nFeatures) rows.
        let ldb = max(n, nFeatures)
        var bx = [Double](repeating: 0.0, count: ldb)
        var by = [Double](repeating: 0.0, count: ldb)
        for row in 0..<n {
            bx[row] = screenPoints[row].x
            by[row] = screenPoints[row].y
        }

        // LAPACK parameters.
        var trans = Int8(UInt8(ascii: "N"))   // No transpose
        var m = __CLPK_integer(n)
        var nCols = __CLPK_integer(nFeatures)
        var nrhs = __CLPK_integer(1)
        var lda = __CLPK_integer(n)
        var ldbParam = __CLPK_integer(ldb)
        var info = __CLPK_integer(0)

        // Workspace query.
        var lwork = __CLPK_integer(-1)
        var workQuery = [Double](repeating: 0.0, count: 1)
        dgels_(&trans, &m, &nCols, &nrhs, &A, &lda,
               &bx, &ldbParam, &workQuery, &lwork, &info)

        // Allocate workspace and solve for x.
        lwork = __CLPK_integer(workQuery[0])
        var workX = [Double](repeating: 0.0, count: Int(lwork))
        var Ax = A  // dgels_ overwrites A; keep a copy for the y solve.
        dgels_(&trans, &m, &nCols, &nrhs, &Ax, &lda,
               &bx, &ldbParam, &workX, &lwork, &info)

        // Solve for y using the original A.
        var Ay = A
        var workY = [Double](repeating: 0.0, count: Int(lwork))
        dgels_(&trans, &m, &nCols, &nrhs, &Ay, &lda,
               &by, &ldbParam, &workY, &lwork, &info)

        let xCoefficients = Array(bx.prefix(nFeatures))
        let yCoefficients = Array(by.prefix(nFeatures))

        return CalibrationProfile(
            xCoefficients: xCoefficients,
            yCoefficients: yCoefficients,
            cameraID: cameraID,
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )
    }

    // MARK: - Outlier rejection

    /// Remove points more than 2 standard deviations from the mean in either axis.
    public static func rejectOutliers(_ points: [GazePoint]) -> [GazePoint] {
        guard points.count > 2 else { return points }

        let xs = points.map(\.x)
        let ys = points.map(\.y)

        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)

        let stdX = standardDeviation(xs, mean: meanX)
        let stdY = standardDeviation(ys, mean: meanY)

        return points.filter {
            abs($0.x - meanX) <= 2.0 * stdX &&
            abs($0.y - meanY) <= 2.0 * stdY
        }
    }

    // MARK: - Private helpers

    private func mean(_ points: [GazePoint]) -> GazePoint {
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        let n = Double(points.count)
        return GazePoint(x: sumX / n, y: sumY / n)
    }

    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0.0 }
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}
