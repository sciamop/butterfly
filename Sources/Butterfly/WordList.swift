import Foundation

/// A sorted list of dictionary words supporting prefix lookups via binary search.
/// Uses a small fraction of the memory a node-per-character trie needs for ~236k words.
class WordList {
    private var words: [String] = []
    private let lock = NSLock()

    init() {
        // Load off the main thread so launch isn't blocked; lookups before it finishes allow everything
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = WordList.loadDictionary()
            self?.lock.lock()
            self?.words = loaded
            self?.lock.unlock()
        }
    }

    private static func loadDictionary() -> [String] {
        let dictionaryPath = "/usr/share/dict/words"
        guard let contents = try? String(contentsOfFile: dictionaryPath, encoding: .utf8) else {
            print("Warning: Could not load system dictionary. Soft bounce filtering is disabled.")
            return []
        }

        var unique = Set<String>()
        contents.enumerateLines { line, _ in
            let word = line.lowercased().trimmingCharacters(in: .whitespaces)
            if !word.isEmpty && word.allSatisfy({ $0.isLetter }) {
                unique.insert(word)
            }
        }

        print("Loaded \(unique.count) words into dictionary")
        return unique.sorted()
    }

    func isValidPrefix(_ prefix: String) -> Bool {
        let prefix = prefix.lowercased()
        lock.lock()
        defer { lock.unlock() }

        // Fail open: never block based on an empty or not-yet-loaded dictionary
        guard !words.isEmpty, !prefix.isEmpty else { return true }

        // Find the first word >= prefix; the prefix is valid if that word starts with it
        var low = 0
        var high = words.count
        while low < high {
            let mid = (low + high) / 2
            if words[mid] < prefix {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low < words.count && words[low].hasPrefix(prefix)
    }
}
