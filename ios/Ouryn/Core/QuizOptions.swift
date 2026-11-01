import Foundation

/// Public BIP39 vocabulary only; never caches a recovery phrase or its answers.
enum QuizOptions {
    static let englishWords: [String] = {
        guard let url = Bundle.main.url(forResource: "bip39-english", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count == 2048, Set(words).count == 2048 else { return [] }
        return words
    }()

    static func get(_ i: Int, _ all: [String]) -> [String] {
        guard all.indices.contains(i), englishWords.contains(all[i]) else { return [] }
        let privateWords = Set(all)
        let others = englishWords.filter { !privateWords.contains($0) }.shuffled().prefix(5)
        guard others.count == 5 else { return [] }
        return ([all[i]] + others).shuffled()
    }
}
