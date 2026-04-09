import Testing
import CoreGraphics
@testable import LucentCore

@Test func mockEstimatorReturnsFaceCenter() {
    let estimator = MockGazeEstimator()
    let faceRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
    let gaze = estimator.estimate(faceBounds: faceRect, leftPupil: CGPoint(x: 0.45, y: 0.5), rightPupil: CGPoint(x: 0.55, y: 0.5))
    #expect(abs(gaze.x - 0.5) < 0.1)
    #expect(abs(gaze.y - 0.5) < 0.1)
}

@Test func mockEstimatorTracksHeadMovement() {
    let estimator = MockGazeEstimator()
    let leftGaze = estimator.estimate(
        faceBounds: CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.4),
        leftPupil: CGPoint(x: 0.25, y: 0.5), rightPupil: CGPoint(x: 0.35, y: 0.5))
    let rightGaze = estimator.estimate(
        faceBounds: CGRect(x: 0.5, y: 0.3, width: 0.4, height: 0.4),
        leftPupil: CGPoint(x: 0.65, y: 0.5), rightPupil: CGPoint(x: 0.75, y: 0.5))
    #expect(rightGaze.x > leftGaze.x)
}
