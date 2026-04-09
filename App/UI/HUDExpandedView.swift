import SwiftUI
import LucentCore

struct HUDExpandedView: View {
    let mode: InputMode
    let confidence: Float
    let expressions: [DetectedExpression]
    let cursorPosition: GazePoint
    let handCount: Int
    let activeGesture: GestureType?
    let handGesturesEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: modeIcon).font(.system(size: 16, weight: .semibold))
                Text(modeName).font(.system(size: 14, weight: .semibold))
                Spacer()
                Circle().fill(confidenceColor).frame(width: 8, height: 8)
                Text("\(Int(confidence * 100))%").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Divider().opacity(0.3)
            if expressions.isEmpty {
                Text("No expressions").font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                ForEach(expressions, id: \.type) { expr in
                    HStack(spacing: 6) {
                        Circle().fill(Color.blue).frame(width: 5, height: 5)
                        Text(expr.type.rawValue).font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text("\(Int(expr.confidence * 100))%").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
            Divider().opacity(0.3)
            HStack {
                Image(systemName: "hand.raised").font(.system(size: 12))
                Text("Hands: \(handCount)").font(.system(size: 11))
                Spacer()
                if let gesture = activeGesture {
                    Text(gesture.rawValue).font(.system(size: 10, design: .monospaced)).foregroundColor(.blue)
                } else {
                    Text(handGesturesEnabled ? "Listening" : "Paused").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            Divider().opacity(0.3)
            HStack {
                Text("Cursor").font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Text("(\(Int(cursorPosition.x)), \(Int(cursorPosition.y)))").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
        }
        .padding(14).frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    private var modeIcon: String {
        switch mode { case .normal: "eye"; case .scroll: "scroll"; case .dictation: "mic"; case .commandPalette: "magnifyingglass"; case .keyboard: "keyboard" }
    }
    private var modeName: String {
        switch mode { case .normal: "Normal"; case .scroll: "Scroll"; case .dictation: "Dictation"; case .commandPalette: "Command Palette"; case .keyboard: "Keyboard" }
    }
    private var confidenceColor: Color {
        if confidence > 0.7 { return .green }; if confidence > 0.4 { return .yellow }; return .red
    }
}
