import SwiftUI
import AppKit
import LucentCore

// MARK: - KeyboardOverlay Panel

final class KeyboardOverlayPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 240),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = contentView
        self.isReleasedWhenClosed = false
    }

    func positionAtBottomCenter(of screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.minY + 20
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// The keyboard portion frame in screen coordinates (excludes prediction bar).
    var keyboardScreenFrame: CGRect {
        let origin = frame.origin
        // Keyboard is the bottom 200pt of the 240pt panel (top 40pt is prediction bar)
        return CGRect(x: origin.x, y: origin.y, width: frame.width, height: 200)
    }
}

// MARK: - Key View

struct KeyView: View {
    let key: KeyDefinition
    let isHovered: Bool
    let isTapped: Bool
    let keyboardWidth: CGFloat
    let keyboardHeight: CGFloat

    var body: some View {
        let w = key.size.width * keyboardWidth
        let h = key.size.height * keyboardHeight

        Text(key.label == "space" ? "________" : key.label)
            .font(.system(size: key.label == "space" ? 14 : 18, weight: isHovered ? .bold : .regular))
            .foregroundColor(.white)
            .frame(width: w - 4, height: h - 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            )
    }

    private var backgroundColor: Color {
        if isTapped { return Color.green.opacity(0.8) }
        if isHovered { return Color.blue.opacity(0.6) }
        return Color.white.opacity(0.15)
    }
}

// MARK: - Keyboard Content View

struct KeyboardContentView: View {
    let keyboard: VirtualKeyboard
    let hoveredKey: KeyDefinition?
    let tappedKey: KeyDefinition?
    let predictions: [String]
    let selectedPredictionIndex: Int?
    let onPredictionTap: (Int) -> Void

    private let keyboardWidth: CGFloat = 600
    private let keyboardHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Prediction bar (40pt)
            PredictionBarView(
                predictions: predictions,
                selectedIndex: selectedPredictionIndex,
                onSelect: onPredictionTap
            )
            .frame(width: keyboardWidth, height: 40)

            // Keyboard layout (200pt)
            ZStack(alignment: .topLeading) {
                // Dark background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.75))

                // Keys
                ForEach(Array(keyboard.keys.enumerated()), id: \.offset) { _, key in
                    KeyView(
                        key: key,
                        isHovered: hoveredKey == key,
                        isTapped: tappedKey == key,
                        keyboardWidth: keyboardWidth,
                        keyboardHeight: keyboardHeight
                    )
                    .position(
                        x: (key.position.x + key.size.width / 2) * keyboardWidth,
                        y: (key.position.y + key.size.height / 2) * keyboardHeight
                    )
                }
            }
            .frame(width: keyboardWidth, height: keyboardHeight)
        }
    }
}
