import SwiftUI
import LucentCore

struct HUDMinimalView: View {
    let mode: InputMode
    let confidence: Float
    let activeExpression: ExpressionType?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: modeIcon).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
            Circle().fill(confidenceColor).frame(width: 6, height: 6)
            if let expr = activeExpression {
                Image(systemName: expressionIcon(expr)).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).transition(.opacity)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    private var modeIcon: String {
        switch mode { case .normal: "eye"; case .scroll: "scroll"; case .dictation: "mic"; case .commandPalette: "magnifyingglass" }
    }
    private var confidenceColor: Color {
        if confidence > 0.7 { return .green }; if confidence > 0.4 { return .yellow }; return .red
    }
    private func expressionIcon(_ type: ExpressionType) -> String {
        switch type { case .winkLeft, .winkRight: "eye.slash"; case .smile: "face.smiling"; case .browRaise: "eyebrow"; case .mouthOpen: "mouth" }
    }
}
