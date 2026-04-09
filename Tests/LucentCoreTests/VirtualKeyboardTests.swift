import Testing
import CoreGraphics
@testable import LucentCore

@Test func qwertyHas27Keys() {
    let kb = VirtualKeyboard.qwerty
    // 10 + 9 + 7 + 1 (space) = 27
    #expect(kb.keys.count == 27)
}

@Test func qwertyHas4Rows() {
    let kb = VirtualKeyboard.qwerty
    #expect(kb.rows == 4)
    let rowCounts = Dictionary(grouping: kb.keys, by: \.row).mapValues(\.count)
    #expect(rowCounts[0] == 10)
    #expect(rowCounts[1] == 9)
    #expect(rowCounts[2] == 7)
    #expect(rowCounts[3] == 1)
}

@Test func noKeysOverlap() {
    let kb = VirtualKeyboard.qwerty
    let epsilon: CGFloat = 1e-9  // tolerance for floating-point edge cases
    for i in 0..<kb.keys.count {
        for j in (i + 1)..<kb.keys.count {
            let a = kb.keys[i]
            let b = kb.keys[j]
            let aRight = a.position.x + a.size.width
            let aBottom = a.position.y + a.size.height
            let bRight = b.position.x + b.size.width
            let bBottom = b.position.y + b.size.height
            let overlapsX = a.position.x < bRight - epsilon && aRight > b.position.x + epsilon
            let overlapsY = a.position.y < bBottom - epsilon && aBottom > b.position.y + epsilon
            if overlapsX && overlapsY {
                Issue.record("Keys \(a.label) and \(b.label) overlap")
            }
        }
    }
}

@Test func allKeyCodesAreUnique() {
    let kb = VirtualKeyboard.qwerty
    let codes = kb.keys.map(\.keyCode)
    let unique = Set(codes)
    #expect(codes.count == unique.count, "Duplicate key codes found")
}

@Test func keyLookupByLabel() {
    let kb = VirtualKeyboard.qwerty
    let q = kb.key(labeled: "Q")
    #expect(q != nil)
    #expect(q?.keyCode == 0x0C)

    let space = kb.key(labeled: "space")
    #expect(space != nil)
    #expect(space?.keyCode == 0x31)
}

@Test func keyCodeMapping() {
    #expect(VirtualKeyboard.keyCode(for: "a") == 0x00)
    #expect(VirtualKeyboard.keyCode(for: "z") == 0x06)
    #expect(VirtualKeyboard.keyCode(for: " ") == 0x31)
    #expect(VirtualKeyboard.keyCode(for: "1") == nil)
}

@Test func keyCentersAreWithinBounds() {
    let kb = VirtualKeyboard.qwerty
    for key in kb.keys {
        let center = key.center
        #expect(center.x >= 0 && center.x <= 1.0, "Key \(key.label) center X out of bounds: \(center.x)")
        #expect(center.y >= 0 && center.y <= 1.0, "Key \(key.label) center Y out of bounds: \(center.y)")
    }
}

@Test func row0StartsAtOrigin() {
    let kb = VirtualKeyboard.qwerty
    let firstKey = kb.keys.first { $0.row == 0 && $0.label == "Q" }
    #expect(firstKey != nil)
    #expect(firstKey!.position.x == 0.0)
    #expect(firstKey!.position.y == 0.0)
}
