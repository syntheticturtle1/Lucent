import Foundation
import CoreGraphics

// MARK: - Key Definition

public struct KeyDefinition: Sendable, Equatable, Hashable {
    public let label: String
    public let keyCode: UInt16
    public let position: CGPoint   // Normalized in keyboard space (0..1, 0..1)
    public let size: CGSize        // Normalized in keyboard space
    public let row: Int

    public init(label: String, keyCode: UInt16, position: CGPoint, size: CGSize, row: Int) {
        self.label = label
        self.keyCode = keyCode
        self.position = position
        self.size = size
        self.row = row
    }

    /// Center point of the key in keyboard-local normalized coordinates.
    public var center: CGPoint {
        CGPoint(x: position.x + size.width / 2.0, y: position.y + size.height / 2.0)
    }
}

// MARK: - Virtual Keyboard

public struct VirtualKeyboard: Sendable {
    public let keys: [KeyDefinition]
    public let rows: Int
    public let columns: Int

    public init(keys: [KeyDefinition], rows: Int, columns: Int) {
        self.keys = keys
        self.rows = rows
        self.columns = columns
    }

    /// Standard QWERTY layout with 4 rows (3 letter rows + space bar).
    public static let qwerty: VirtualKeyboard = {
        var keys: [KeyDefinition] = []

        let keyWidth: CGFloat = 0.1
        let keyHeight: CGFloat = 0.25
        let keySize = CGSize(width: keyWidth, height: keyHeight)

        // Row 0: Q W E R T Y U I O P (10 keys, no stagger)
        let row0Letters: [(String, UInt16)] = [
            ("Q", 0x0C), ("W", 0x0D), ("E", 0x0E), ("R", 0x0F), ("T", 0x11),
            ("Y", 0x10), ("U", 0x20), ("I", 0x22), ("O", 0x1F), ("P", 0x23),
        ]
        let row0Stagger: CGFloat = 0.0
        for (i, (label, code)) in row0Letters.enumerated() {
            let x = row0Stagger + CGFloat(i) * keyWidth
            let y: CGFloat = 0.0
            keys.append(KeyDefinition(label: label, keyCode: code, position: CGPoint(x: x, y: y), size: keySize, row: 0))
        }

        // Row 1: A S D F G H J K L (9 keys, 0.05 stagger)
        let row1Letters: [(String, UInt16)] = [
            ("A", 0x00), ("S", 0x01), ("D", 0x02), ("F", 0x03), ("G", 0x05),
            ("H", 0x04), ("J", 0x26), ("K", 0x28), ("L", 0x25),
        ]
        let row1Stagger: CGFloat = 0.05
        for (i, (label, code)) in row1Letters.enumerated() {
            let x = row1Stagger + CGFloat(i) * keyWidth
            let y: CGFloat = keyHeight
            keys.append(KeyDefinition(label: label, keyCode: code, position: CGPoint(x: x, y: y), size: keySize, row: 1))
        }

        // Row 2: Z X C V B N M (7 keys, 0.15 stagger)
        let row2Letters: [(String, UInt16)] = [
            ("Z", 0x06), ("X", 0x07), ("C", 0x08), ("V", 0x09), ("B", 0x0B),
            ("N", 0x2D), ("M", 0x2E),
        ]
        let row2Stagger: CGFloat = 0.15
        for (i, (label, code)) in row2Letters.enumerated() {
            let x = row2Stagger + CGFloat(i) * keyWidth
            let y: CGFloat = keyHeight * 2
            keys.append(KeyDefinition(label: label, keyCode: code, position: CGPoint(x: x, y: y), size: keySize, row: 2))
        }

        // Row 3: Space bar (60% width, centered)
        let spaceWidth: CGFloat = 0.6
        let spaceX: CGFloat = 0.2  // Centered: (1.0 - 0.6) / 2
        keys.append(KeyDefinition(
            label: "space",
            keyCode: 0x31,
            position: CGPoint(x: spaceX, y: keyHeight * 3),
            size: CGSize(width: spaceWidth, height: keyHeight),
            row: 3
        ))

        return VirtualKeyboard(keys: keys, rows: 4, columns: 10)
    }()

    /// Look up a KeyDefinition by its label (case-insensitive).
    public func key(labeled label: String) -> KeyDefinition? {
        keys.first { $0.label.lowercased() == label.lowercased() }
    }

    /// Look up a KeyDefinition by its keyCode.
    public func key(forKeyCode keyCode: UInt16) -> KeyDefinition? {
        keys.first { $0.keyCode == keyCode }
    }

    /// Map a character (e.g. "a") to its macOS virtual keyCode.
    public static func keyCode(for character: Character) -> UInt16? {
        let charMap: [Character: UInt16] = [
            "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
            "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
            "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
            "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
            "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
            "z": 0x06, " ": 0x31,
        ]
        return charMap[character]
    }
}
