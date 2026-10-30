#if os(macOS)
import Foundation

/// Rule-based clock times and durations from a transcript. The language model is unreliable on these (it reads
/// "an hour and a half" as 60 and often leaves `hasMinutes` false), and they are regular enough for rules to do
/// better. `VoiceDraftMapper` lets a rule result win over the model's.
nonisolated enum VoiceTimeParser {
    // MARK: Arrival ("i arrived at 2 pm" → "14:00")

    /// `HH:mm` for the first arrival-style clock time in `transcript`, or nil. Matches "2 pm", "2:30 p.m.", "14:30",
    /// "at noon" and "9 in the morning". Times introduced by leaving words ("left at 5 pm", "until 6") are skipped,
    /// and a bare "at 2" is left to the model because the half of the day is unknown.
    static func arrival(in transcript: String) -> String? {
        let text = normalize(transcript)
        var found: [(location: Int, hour: Int, minute: Int)] = []

        for m in matches(#"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#, in: text) {
            guard let h = int(m, 1, in: text), (1...12).contains(h) else { continue }
            let min = int(m, 2, in: text) ?? 0
            guard (0..<60).contains(min) else { continue }
            found.append((m.range.location, to24(h, pm: string(m, 3, in: text) == "pm"), min))
        }
        for m in matches(#"\b([01]?\d|2[0-3]):([0-5]\d)\b(?!\s*(?:hours?|hrs?|minutes?|mins?))"#, in: text) {
            guard let h = int(m, 1, in: text), let min = int(m, 2, in: text) else { continue }
            found.append((m.range.location, h, min))
        }
        for m in matches(#"\b(?:at|around|by|about)\s+(?:the\s+)?(noon|midnight)\b"#, in: text) {
            found.append((m.range.location, string(m, 1, in: text) == "noon" ? 12 : 0, 0))
        }
        for m in matches(#"\b(\d{1,2})\s*(?:o'?clock\s*)?in the (morning|afternoon|evening)\b"#, in: text) {
            guard let h = int(m, 1, in: text), (1...12).contains(h) else { continue }
            found.append((m.range.location, to24(h, pm: string(m, 2, in: text) != "morning"), 0))
        }

        let leaving = #"\b(left|leave|leaving|until|till|departed|depart|closes|closed|checked out|ended|end)\b"#
        let pick = found.sorted { $0.location < $1.location }.first { c in
            let before = String(text.prefix(c.location)).split(separator: " ").suffix(3).joined(separator: " ")
            return before.range(of: leaving, options: .regularExpression) == nil
        }
        return pick.map { String(format: "%02d:%02d", $0.hour, $0.minute) }
    }

    private static func to24(_ hour: Int, pm: Bool) -> Int {
        if pm { return hour == 12 ? 12 : hour + 12 }
        return hour == 12 ? 0 : hour
    }

    // MARK: Time spent ("about an hour and a half" → 90)

    enum Duration: Equatable {
        case minutes(Int)
        /// Durations were spoken but all describe travelling, so they must not become "time spent".
        case travelOnly
        case none
    }

    static func minutes(in transcript: String) -> Int? {
        if case .minutes(let m) = duration(in: transcript) { return m }
        return nil
    }

    static func duration(in transcript: String) -> Duration {
        var text = normalize(transcript)
        text = replacing(#"\b(?:three quarters|3 quarters) of an hour\b"#, in: text) { _ in "45 minutes" }
        text = replacing(#"\b(?:a )?quarter (?:of an |of a |an )?hour\b"#, in: text) { _ in "15 minutes" }
        text = replacing(#"\bhalf (?:an |a )?hour\b"#, in: text) { _ in "30 minutes" }
        text = replacing(#"\b(?:an?|1) hour and a half\b"#, in: text) { _ in "90 minutes" }
        text = replacing(#"\b(\d+) hours? and a half\b"#, in: text) { g in "\((Int(g[1]) ?? 0) * 60 + 30) minutes" }
        text = replacing(#"\b(?:an?|1) hour\b"#, in: text) { _ in "1 hour" }
        text = replacing(#"\bcouple of hours\b"#, in: text) { _ in "2 hours" }

        var candidates: [(range: NSRange, value: Int)] = []
        for m in matches(#"\b(\d+(?:\.\d+)?)\s*(?:hours?|hrs?)\b(?:\s*(?:and\s*)?(\d+)\s*(?:minutes?|mins?)\b)?"#, in: text) {
            guard let hours = Double(string(m, 1, in: text) ?? "") else { continue }
            candidates.append((m.range, Int((hours * 60).rounded()) + (int(m, 2, in: text) ?? 0)))
        }
        for m in matches(#"\b(\d+)\s*(?:minutes?|mins?)\b"#, in: text) {
            guard !candidates.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }),
                  let v = int(m, 1, in: text) else { continue }
            candidates.append((m.range, v))
        }
        candidates.sort { $0.range.location < $1.range.location }
        if candidates.isEmpty { return .none }

        let ns = text as NSString
        for c in candidates where !isTravel(before: ns.substring(to: c.range.location),
                                            after: ns.substring(from: c.range.location + c.range.length)) {
            return .minutes(min(max(c.value, 0), 24 * 60))
        }
        return .travelOnly
    }

    /// A duration is travel when a travel word is right beside it (two words before, three after: "walked 20 minutes",
    /// "20 minutes by auto", "took an hour to reach") and no "spent/stayed" cue comes just before it. The narrow
    /// window keeps run-ons like "took a cab, 90 rupees, 2 hours" from counting as travel.
    private static func isTravel(before: String, after: String) -> Bool {
        let words = before.split(separator: " ")
        let stay = #"\b(spent|spend|stayed|stay|hung around|lingered|explored|wandered|visit|visited)\b"#
        if words.suffix(3).joined(separator: " ").range(of: stay, options: .regularExpression) != nil { return false }
        let travel = #"\b(walk|walked|walking|ride|rode|drive|drove|driving|cab|taxi|auto|bus|train|metro|ferry|flight|flew|travel|travelled|traveled|commute|commuted|journey|away|get there|to get|to reach|reach)\b"#
        let near = (words.suffix(2) + after.split(separator: " ").prefix(3)).joined(separator: " ")
        return near.range(of: travel, options: .regularExpression) != nil
    }

    // MARK: Helpers

    /// Lower case, "p.m." → "pm", hyphens as spaces, and spoken numbers ("forty five") as digits.
    private static func normalize(_ transcript: String) -> String {
        var s = transcript.lowercased().replacingOccurrences(of: "-", with: " ")
        s = replacing(#"\b([ap])\.\s?m\.?"#, in: s) { g in g[1] + "m" }
        s = s.replacingOccurrences(of: "o’clock", with: "o'clock")
        return digitizeNumberWords(s)
    }

    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80,
        "ninety": 90]

    private static func digitizeNumberWords(_ s: String) -> String {
        let tokens = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            let bare = t.trimmingCharacters(in: .punctuationCharacters)
            let trailing = String(t.dropFirst(bare.count))
            if let ten = tens[bare] {
                if i + 1 < tokens.count, trailing.isEmpty, let u = units[tokens[i + 1]], (1..<10).contains(u) {
                    out.append(String(ten + u)); i += 2; continue
                }
                out.append(String(ten) + trailing)
            } else if let u = units[bare] {
                out.append(String(u) + trailing)
            } else {
                out.append(t)
            }
            i += 1
        }
        return out.joined(separator: " ")
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func replacing(_ pattern: String, in text: String, with transform: ([String]) -> String) -> String {
        var result = text
        for m in matches(pattern, in: text).reversed() {
            let groups = (0..<m.numberOfRanges).map { string(m, $0, in: text) ?? "" }
            guard let r = Range(m.range, in: result) else { continue }
            result.replaceSubrange(r, with: transform(groups))
        }
        return result
    }

    private static func string(_ m: NSTextCheckingResult, _ i: Int, in text: String) -> String? {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: text) else { return nil }
        return String(text[r])
    }

    private static func int(_ m: NSTextCheckingResult, _ i: Int, in text: String) -> Int? {
        string(m, i, in: text).flatMap { Int($0) }
    }
}
#endif
