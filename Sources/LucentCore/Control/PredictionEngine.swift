import Foundation

public final class PredictionEngine: Sendable {

    private let sortedWords: [(word: String, frequency: Int)]

    /// Initialize from the bundled words.txt resource.
    public init() {
        if let url = Bundle.module.url(forResource: "words", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            self.sortedWords = PredictionEngine.parse(content)
        } else {
            self.sortedWords = []
        }
    }

    /// Initialize with an explicit word list (for testing).
    public init(words: [(word: String, frequency: Int)]) {
        self.sortedWords = words.sorted { $0.frequency > $1.frequency }
    }

    /// Return up to `maxResults` word completions for the given prefix, sorted by frequency descending.
    public func predict(prefix: String, maxResults: Int = 3) -> [String] {
        guard !prefix.isEmpty else { return [] }

        let lowered = prefix.lowercased()
        var results: [String] = []

        for entry in sortedWords {
            if entry.word.lowercased().hasPrefix(lowered) {
                results.append(entry.word)
                if results.count >= maxResults { break }
            }
        }

        return results
    }

    // MARK: - Parsing

    private static func parse(_ content: String) -> [(word: String, frequency: Int)] {
        var entries: [(word: String, frequency: Int)] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2,
                  let freq = Int(parts[1]) else { continue }

            entries.append((word: String(parts[0]), frequency: freq))
        }

        return entries.sorted { $0.frequency > $1.frequency }
    }
}
