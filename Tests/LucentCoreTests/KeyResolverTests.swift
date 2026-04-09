import Testing
import CoreGraphics
@testable import LucentCore

// MARK: - Test Helpers

private let testKeyboardFrame = CGRect(x: 100, y: 600, width: 600, height: 200)

// MARK: - Tests

@Test func resolvesExactKeyCenter() {
    let resolver = KeyResolver()
    let kb = VirtualKeyboard.qwerty
    // Key "Q" is at position (0.0, 0.0) with size (0.1, 0.25)
    // Center in keyboard space: (0.05, 0.125)
    // Screen position: (100 + 0.05*600, 600 + 0.125*200) = (130, 625)
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 130, y: 625),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result != nil)
    #expect(result?.label == "Q")
}

@Test func resolvesNearbyPosition() {
    let resolver = KeyResolver()
    // Slightly off from Q center but within hit radius
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 135, y: 630),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result != nil)
    #expect(result?.label == "Q")
}

@Test func returnsNilForOutOfBoundsPosition() {
    let resolver = KeyResolver()
    // Way outside the keyboard
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 50, y: 300),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result == nil)
}

@Test func resolvesSpaceBar() {
    let resolver = KeyResolver()
    // Space bar center: position (0.2, 0.75), size (0.6, 0.25)
    // Center in keyboard space: (0.5, 0.875)
    // Screen: (100 + 0.5*600, 600 + 0.875*200) = (400, 775)
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 400, y: 775),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result != nil)
    #expect(result?.label == "space")
}

@Test func resolvesRow1WithStagger() {
    let resolver = KeyResolver()
    // Key "A" is at position (0.05, 0.25) with size (0.1, 0.25)
    // Center: (0.10, 0.375)
    // Screen: (100 + 0.10*600, 600 + 0.375*200) = (160, 675)
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 160, y: 675),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result != nil)
    #expect(result?.label == "A")
}

@Test func resolvesRow2WithStagger() {
    let resolver = KeyResolver()
    // Key "Z" is at position (0.15, 0.5) with size (0.1, 0.25)
    // Center: (0.20, 0.625)
    // Screen: (100 + 0.20*600, 600 + 0.625*200) = (220, 725)
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 220, y: 725),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result != nil)
    #expect(result?.label == "Z")
}

@Test func nearestKeyReturnsClosestWithDistance() {
    let resolver = KeyResolver()
    let result = resolver.nearestKey(localPosition: CGPoint(x: 0.05, y: 0.125))
    #expect(result != nil)
    #expect(result?.key.label == "Q")
    #expect(result!.distance < 0.01)
}

@Test func fuzzyMarginAllowsSlightlyOutsideKeyboard() {
    let config = KeyResolverConfig(fuzzyMargin: 0.05, maxHitRadius: 0.08)
    let resolver = KeyResolver(config: config)
    // Position slightly to the left of keyboard bounds
    // Screen X = 100 - 10 = 90 -> localX = -10/600 = -0.017 (within fuzzyMargin of 0.05)
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 90, y: 625),
        keyboardFrame: testKeyboardFrame
    )
    // Should still match Q since it's within fuzzy margin and hit radius
    #expect(result != nil)
    #expect(result?.label == "Q")
}

@Test func tooFarFromAnyKeyReturnsNil() {
    let config = KeyResolverConfig(fuzzyMargin: 0.05, maxHitRadius: 0.02)  // Very tight radius
    let resolver = KeyResolver(config: config)
    // Position between Q and W but with tight radius should still match one
    // Midpoint between Q center (0.05, 0.125) and W center (0.15, 0.125): (0.10, 0.125)
    // Distance to Q = 0.05, distance to W = 0.05 -- both exceed maxHitRadius of 0.02
    let result = resolver.resolve(
        fingertipScreenPosition: CGPoint(x: 160, y: 625),
        keyboardFrame: testKeyboardFrame
    )
    #expect(result == nil)
}
