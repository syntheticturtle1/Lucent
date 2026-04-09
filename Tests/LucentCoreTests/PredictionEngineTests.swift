import Testing
@testable import LucentCore

// MARK: - Tests using explicit word list (for deterministic testing)

private let testWords: [(word: String, frequency: Int)] = [
    ("the", 1000),
    ("they", 800),
    ("them", 700),
    ("then", 600),
    ("there", 500),
    ("these", 400),
    ("think", 300),
    ("this", 200),
    ("three", 100),
    ("apple", 900),
    ("application", 850),
    ("apply", 800),
    ("app", 750),
    ("hello", 500),
    ("help", 450),
    ("world", 300),
]

@Test func predictReturnsTopByFrequency() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "th")
    #expect(results.count == 3)
    #expect(results[0] == "the")
    #expect(results[1] == "they")
    #expect(results[2] == "them")
}

@Test func predictIsCaseInsensitive() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "TH")
    #expect(results.count == 3)
    #expect(results[0] == "the")
}

@Test func predictReturnsEmptyForEmptyPrefix() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "")
    #expect(results.isEmpty)
}

@Test func predictReturnsEmptyForNoMatch() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "xyz")
    #expect(results.isEmpty)
}

@Test func predictRespectsMaxResults() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "th", maxResults: 2)
    #expect(results.count == 2)
}

@Test func predictWithExactMatch() {
    let engine = PredictionEngine(words: testWords)
    // "the" is an exact match and also a prefix of "they", "them", "then", "there", "these", "three"
    let results = engine.predict(prefix: "the")
    #expect(results.count == 3)
    #expect(results[0] == "the")  // Exact match, highest frequency
    #expect(results[1] == "they")
    #expect(results[2] == "them")
}

@Test func predictSingleCharPrefix() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "a")
    #expect(results.count == 3)
    #expect(results[0] == "apple")   // 900
    #expect(results[1] == "application")  // 850
    #expect(results[2] == "apply")   // 800
}

@Test func predictWithFullWord() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "hello")
    #expect(results.count == 1)
    #expect(results[0] == "hello")
}

@Test func predictLongerThanAnyWord() {
    let engine = PredictionEngine(words: testWords)
    let results = engine.predict(prefix: "applications")
    #expect(results.isEmpty)
}

@Test func bundledDictionaryLoads() {
    // This tests loading from the actual bundle resource
    let engine = PredictionEngine()
    let results = engine.predict(prefix: "the")
    #expect(!results.isEmpty, "Bundled dictionary should have words starting with 'the'")
}
