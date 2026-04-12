import Testing
import CoreGraphics
import CoreVideo
@testable import LucentCore

private func makeDummyBuffer() -> CVPixelBuffer {
    var buf: CVPixelBuffer?
    CVPixelBufferCreate(nil, 640, 480, kCVPixelFormatType_32BGRA, nil, &buf)
    return buf!
}

@Test func mockEstimatorReturnsCenterOnFirstFrame() {
    let estimator = MockGazeEstimator()
    let faceRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
    let result = estimator.estimate(
        pixelBuffer: makeDummyBuffer(),
        faceBounds: faceRect,
        leftPupil: CGPoint(x: 0.45, y: 0.5),
        rightPupil: CGPoint(x: 0.55, y: 0.5)
    )
    // First frame should land near center (0.5, 0.5)
    #expect(abs(result.position.x - 0.5) < 0.3)
    #expect(abs(result.position.y - 0.5) < 0.3)
}

@Test func mockEstimatorDetectsSaccade() {
    let estimator = MockGazeEstimator()
    let buf = makeDummyBuffer()

    // Send several frames with pupils at center to establish baseline
    for _ in 0..<10 {
        _ = estimator.estimate(
            pixelBuffer: buf,
            faceBounds: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            leftPupil: CGPoint(x: 0.45, y: 0.5),
            rightPupil: CGPoint(x: 0.55, y: 0.5)
        )
    }

    // Now jump pupils far to the right — should trigger saccade (teleport)
    let result = estimator.estimate(
        pixelBuffer: buf,
        faceBounds: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
        leftPupil: CGPoint(x: 0.35, y: 0.5),
        rightPupil: CGPoint(x: 0.40, y: 0.5)
    )
    #expect(result.isTeleport == true)
}
