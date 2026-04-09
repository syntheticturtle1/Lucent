import Foundation

/// Smooths raw gaze point input using a Kalman filter, dwell zones, and velocity scaling.
///
/// Pipeline per call to `smooth(_:)`:
///   1. Kalman predict (propagate state forward by dt = 1/30 s)
///   2. Velocity-scaled Kalman update (trust measurement more for fast saccades)
///   3. Dwell-zone locking (freeze cursor when gaze dwells in one area)
public final class CursorSmoother {

    // MARK: - Configuration

    private let dwellRadius: Double
    private let dwellTime: Double
    private let processNoise: Double
    private let measurementNoise: Double

    /// Fixed timestep (30 fps)
    private let dt: Double = 1.0 / 30.0

    // MARK: - Kalman state  [x, y, vx, vy]

    /// State estimate vector
    private var state: [Double] = [0, 0, 0, 0]

    /// 4x4 covariance matrix (row-major)
    private var P: [[Double]] = {
        var p = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
        for i in 0..<4 { p[i][i] = 500.0 }
        return p
    }()

    /// Whether the filter has been seeded with a first measurement
    private var initialized = false

    // MARK: - Dwell zone state

    private var dwellCenter: GazePoint?
    private var dwellEntryTime: Date?
    private var isDwelling = false

    // MARK: - Init

    public init(dwellRadius: Double = 30,
                dwellTime: Double = 0.2,
                processNoise: Double = 2.0,
                measurementNoise: Double = 8.0) {
        self.dwellRadius = dwellRadius
        self.dwellTime = dwellTime
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }

    // MARK: - Public API

    /// Apply Kalman smoothing, dwell locking, and return a filtered GazePoint.
    public func smooth(_ raw: GazePoint) -> GazePoint {
        // Seed filter on first call
        if !initialized {
            state = [raw.x, raw.y, 0, 0]
            initialized = true
            return raw
        }

        // --- Kalman Predict ---
        kalmanPredict()

        // --- Velocity-scaled measurement noise ---
        let predicted = GazePoint(x: state[0], y: state[1])
        let jumpDistance = raw.distance(to: predicted)
        // Large jumps → trust the measurement more (lower noise), smoothing is reduced.
        // Small movements → keep high noise, smoothing is preserved.
        let scaledMeasurementNoise = max(1.0, measurementNoise - jumpDistance * 0.05)

        // --- Kalman Update ---
        kalmanUpdate(measurement: raw, measurementNoise: scaledMeasurementNoise)

        var smoothed = GazePoint(x: state[0], y: state[1])

        // --- Dwell Zone ---
        smoothed = applyDwellZone(smoothed: smoothed, raw: raw)

        return smoothed
    }

    // MARK: - Kalman internals

    /// Predict step: advance state by dt using constant-velocity model.
    private func kalmanPredict() {
        // F = [[1, 0, dt, 0],
        //      [0, 1, 0, dt],
        //      [0, 0, 1,  0],
        //      [0, 0, 0,  1]]
        let newX  = state[0] + state[2] * dt
        let newY  = state[1] + state[3] * dt
        let newVx = state[2]
        let newVy = state[3]
        state = [newX, newY, newVx, newVy]

        // P = F*P*F' + Q
        // F*P: rows 0,1 get dt * rows 2,3 added; rows 2,3 stay.
        var FP = P
        for j in 0..<4 {
            FP[0][j] = P[0][j] + dt * P[2][j]
            FP[1][j] = P[1][j] + dt * P[3][j]
        }
        // (F*P)*F': cols 0,1 get dt * cols 2,3 added.
        var FPFt = FP
        for i in 0..<4 {
            FPFt[i][0] = FP[i][0] + dt * FP[i][2]
            FPFt[i][1] = FP[i][1] + dt * FP[i][3]
        }
        // Add process noise Q (diagonal)
        let q = processNoise
        let qv = processNoise * 0.5
        FPFt[0][0] += q
        FPFt[1][1] += q
        FPFt[2][2] += qv
        FPFt[3][3] += qv
        P = FPFt
    }

    /// Update step: 2D position observation (H observes x, y only).
    private func kalmanUpdate(measurement: GazePoint, measurementNoise: Double) {
        // H = [[1, 0, 0, 0],
        //      [0, 1, 0, 0]]
        // S = H*P*H' + R  (2x2)
        let r = measurementNoise * measurementNoise
        let s00 = P[0][0] + r
        let s01 = P[0][1]
        let s10 = P[1][0]
        let s11 = P[1][1] + r

        // S^-1 (2x2 matrix inverse)
        let det = s00 * s11 - s01 * s10
        guard abs(det) > 1e-10 else { return }
        let si00 =  s11 / det
        let si01 = -s01 / det
        let si10 = -s10 / det
        let si11 =  s00 / det

        // K = P * H' * S^-1  (4x2)
        // P*H': first two columns of P
        // K[i][0] = P[i][0]*si00 + P[i][1]*si10
        // K[i][1] = P[i][0]*si01 + P[i][1]*si11
        var K = Array(repeating: Array(repeating: 0.0, count: 2), count: 4)
        for i in 0..<4 {
            K[i][0] = P[i][0] * si00 + P[i][1] * si10
            K[i][1] = P[i][0] * si01 + P[i][1] * si11
        }

        // Innovation y = z - H*x
        let iy = measurement.x - state[0]
        let iz = measurement.y - state[1]

        // State update
        for i in 0..<4 {
            state[i] += K[i][0] * iy + K[i][1] * iz
        }

        // Covariance update P = (I - K*H) * P
        // K*H is 4x4; only first 2 cols of H are non-zero
        var newP = P
        for i in 0..<4 {
            for j in 0..<4 {
                let kh_ij = K[i][0] * (j == 0 ? 1.0 : 0.0) + K[i][1] * (j == 1 ? 1.0 : 0.0)
                newP[i][j] = (i == j ? 1.0 : 0.0) * P[i][j] - kh_ij * P[i][j]
            }
        }
        // Correct formula: newP[i][j] = sum_k (delta_ik - K[i][0]*H[0][k] - K[i][1]*H[1][k]) * P[k][j]
        // H[0][k] = 1 if k==0, H[1][k] = 1 if k==1
        var newP2 = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                var sum = 0.0
                for k in 0..<4 {
                    let ikFactor: Double = (i == k) ? 1.0 : 0.0
                    let khFactor = K[i][0] * (k == 0 ? 1.0 : 0.0) + K[i][1] * (k == 1 ? 1.0 : 0.0)
                    sum += (ikFactor - khFactor) * P[k][j]
                }
                newP2[i][j] = sum
            }
        }
        P = newP2
    }

    // MARK: - Dwell zone

    private func applyDwellZone(smoothed: GazePoint, raw: GazePoint) -> GazePoint {
        let now = Date()

        if let center = dwellCenter {
            let distToCenter = raw.distance(to: center)

            if distToCenter <= dwellRadius {
                // Still within dwell zone
                let elapsed = dwellEntryTime.map { now.timeIntervalSince($0) } ?? 0
                if elapsed >= dwellTime {
                    isDwelling = true
                }
                if isDwelling {
                    return center
                }
            } else {
                // Exited dwell zone — reset
                isDwelling = false
                dwellCenter = smoothed
                dwellEntryTime = now
            }
        } else {
            // First call
            dwellCenter = smoothed
            dwellEntryTime = now
        }

        return smoothed
    }
}
