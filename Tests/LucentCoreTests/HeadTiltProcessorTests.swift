import Testing
@testable import LucentCore

@Test func noOffsetWhenLevel() {
    let processor = HeadTiltProcessor()
    let offset = processor.process(rollDegrees: 0.0)
    #expect(abs(offset.x) < 0.001)
    #expect(abs(offset.y) < 0.001)
}

@Test func noOffsetInDeadZone() {
    let processor = HeadTiltProcessor()
    let offset = processor.process(rollDegrees: 2.0)
    #expect(abs(offset.x) < 0.001)
}

@Test func offsetRightWhenTiltedRight() {
    let processor = HeadTiltProcessor()
    let offset = processor.process(rollDegrees: 10.0)
    #expect(offset.x > 3.0)
}

@Test func offsetLeftWhenTiltedLeft() {
    let processor = HeadTiltProcessor()
    let offset = processor.process(rollDegrees: -10.0)
    #expect(offset.x < -3.0)
}

@Test func largerTiltProducesLargerOffset() {
    let processor = HeadTiltProcessor()
    let small = processor.process(rollDegrees: 10.0)
    let large = processor.process(rollDegrees: 20.0)
    #expect(large.x > small.x)
}

@Test func disabledReturnsZero() {
    let processor = HeadTiltProcessor()
    processor.isEnabled = false
    let offset = processor.process(rollDegrees: 15.0)
    #expect(abs(offset.x) < 0.001)
}
