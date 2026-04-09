import SwiftUI
import LucentCore

struct HUDMinimalView: View {
    let mode: InputMode
    let confidence: Float
    let activeExpression: ExpressionType?
    let activeGesture: GestureType?
    let handDetected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: modeIcon).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
            Circle().fill(confidenceColor).frame(width: 6, height: 6)
            if let expr = activeExpression {
                Image(systemName: expressionIcon(expr)).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).transition(.opacity)
            }
            if handDetected {
                Image(systemName: gestureIcon).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).transition(.opacity)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    private var modeIcon: String {
        switch mode { case .normal: "eye"; case .scroll: "scroll"; case .dictation: "mic"; case .commandPalette: "magnifyingglass"; case .keyboard: "keyboard" }
    }
    private var confidenceColor: Color {
        if confidence > 0.7 { return .green }; if confidence > 0.4 { return .yellow }; return .red
    }
    private func expressionIcon(_ type: ExpressionType) -> String {
        switch type { case .winkLeft, .winkRight: "eye.slash"; case .smile: "face.smiling"; case .browRaise: "eyebrow"; case .mouthOpen: "mouth" }
    }
    private var gestureIcon: String {
        guard let gesture = activeGesture else { return "hand.raised" }
        switch gesture {
        case .swipeLeft, .swipeRight: return "hand.point.left"
        case .swipeUp, .swipeDown: return "hand.point.up"
        case .pinch: return "hand.pinch"
        case .fist: return "hand.closed"
        case .point: return "hand.point.right"
        case .openPalm: return "hand.raised"
        }
    }
}
