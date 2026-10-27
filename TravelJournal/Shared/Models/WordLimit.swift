import Foundation

enum WordLimit {
    static let stopStory = 100

    static func count(_ text: String) -> Int {
        var n = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { _, _, _, _ in n += 1 }
        return n
    }

    /// Text cut right after the `limit`-th word; unchanged if within the limit.
    static func truncated(_ text: String, to limit: Int = stopStory) -> String {
        guard limit > 0 else { return "" }
        var n = 0
        var end: String.Index?
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { _, r, _, stop in
            n += 1
            if n == limit { end = r.upperBound; stop = true }
        }
        guard let end else { return text }
        let rest = text[end...]
        // Already exactly at the limit (no further word): keep original text untouched.
        if count(String(rest)) == 0 { return text }
        return String(text[..<end])
    }

    static func remaining(_ text: String, limit: Int = stopStory) -> Int { limit - count(text) }
    static func isWithin(_ text: String, limit: Int = stopStory) -> Bool { count(text) <= limit }
}
