import SwiftUI
import LucentCore

struct PredictionBarView: View {
    let predictions: [String]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if predictions.isEmpty {
                Text("Start typing...")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(predictions.enumerated()), id: \.offset) { index, word in
                    PredictionItemView(
                        word: word,
                        isSelected: selectedIndex == index,
                        onSelect: { onSelect(index) }
                    )
                    if index < predictions.count - 1 {
                        Divider()
                            .frame(height: 24)
                            .background(Color.white.opacity(0.2))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
        )
    }
}

struct PredictionItemView: View {
    let word: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(word)
                .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue.opacity(0.4) : Color.clear)
                        .padding(2)
                )
        }
        .buttonStyle(.plain)
    }
}
