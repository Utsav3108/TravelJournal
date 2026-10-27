import Foundation
import CoreGraphics

/// Shortens story text for Story frames (the PDF and carousel keep the full text). Pure.
///
/// A Story frame has about 420 pt between Instagram's clear bands, so when a stop does not fit, its story card is
/// cut to the first sentence (the highlight strip stays as its own element, so the frame reads highlight + first
/// sentence). The text is never longer than the original and never cut mid-word.
nonisolated enum StoryTrim {
    /// Longest trimmed text, in words, before an ellipsis is added to a very long first sentence.
    static let maxWords = 28

    private static let terminators: Set<Character> = [".", "!", "?", "\u{2026}", "\u{3002}", "\u{FF01}", "\u{FF1F}"]
    private static let closers: Set<Character> = ["\"", "'", ")", "]", "\u{201D}", "\u{2019}", "\u{00BB}"]
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "st", "mt", "sr", "jr", "vs", "etc", "no", "approx", "fig", "e.g", "i.e", "a.m", "p.m",
    ]

    /// The first sentence of `text`, capped at `maxWords` words (with an ellipsis when it had to be cut).
    static func firstSentence(_ text: String, maxWords: Int = StoryTrim.maxWords) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let chars = Array(trimmed)
        var end = chars.count
        var i = 0
        scan: while i < chars.count {
            let c = chars[i]
            if c == "\n", i > 0 {
                end = i
                break scan
            }
            if terminators.contains(c) {
                var j = i
                while j + 1 < chars.count, terminators.contains(chars[j + 1]) { j += 1 }
                while j + 1 < chars.count, closers.contains(chars[j + 1]) { j += 1 }
                let atEnd = j + 1 >= chars.count
                let spaceAfter = !atEnd && chars[j + 1].isWhitespace
                let cjk = c == "\u{3002}" || c == "\u{FF01}" || c == "\u{FF1F}"
                if atEnd || spaceAfter || cjk, !(c == "." && isAbbreviation(chars, endingAt: i)) {
                    end = j + 1
                    break scan
                }
                i = j
            }
            i += 1
        }
        return capWords(String(chars[0..<end]).trimmingCharacters(in: .whitespacesAndNewlines), maxWords: maxWords)
    }

    /// The text a Story frame prints for `story`: the first sentence. (Highlights are separate strips.)
    static func trimmed(_ story: String) -> String { firstSentence(story) }

    /// `text` cut at a word boundary, with an ellipsis, so it wraps to at most `maxLines` lines. Unchanged when it fits.
    static func clamp(_ text: String, fontName: String, size: CGFloat, lineSpacing: CGFloat, width: CGFloat,
                      maxLines: Int) -> String {
        let lines = max(1, maxLines)
        let oneLine = PageText.height("Ag", fontName: fontName, size: size, lineSpacing: 0, width: width)
        let limit = oneLine * CGFloat(lines) + lineSpacing * CGFloat(lines - 1) + 0.5
        func fits(_ s: String) -> Bool {
            PageText.height(s, fontName: fontName, size: size, lineSpacing: lineSpacing, width: width) <= limit
        }
        if fits(text) { return text }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var lo = 0, hi = words.count      // largest word count whose text + ellipsis fits
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if fits(ellipsized(words.prefix(mid).joined(separator: " "))) { lo = mid } else { hi = mid - 1 }
        }
        return ellipsized(words.prefix(max(lo, 1)).joined(separator: " "))
    }

    // MARK: Helpers

    private static func isAbbreviation(_ chars: [Character], endingAt dot: Int) -> Bool {
        var k = dot
        var word = ""
        while k > 0, !chars[k - 1].isWhitespace { k -= 1; word.insert(chars[k], at: word.startIndex) }
        word = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'([\u{201C}\u{2018}"))
        if abbreviations.contains(word.lowercased()) { return true }
        if word.count == 1, word.first?.isLetter == true { return true }              // initials: "J. K. Rowling"
        return false
    }

    private static func capWords(_ s: String, maxWords: Int) -> String {
        let words = s.split(whereSeparator: { $0.isWhitespace })
        guard words.count > maxWords else { return s }
        return ellipsized(words.prefix(maxWords).joined(separator: " "))
    }

    private static func ellipsized(_ s: String) -> String {
        var t = s
        while let last = t.last, ",;:-\u{2013}\u{2014} .".contains(last) { t.removeLast() }
        return t + "\u{2026}"
    }
}
