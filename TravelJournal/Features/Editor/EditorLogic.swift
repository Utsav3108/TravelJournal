import Foundation
import SwiftUI

/// Pure, unit-tested helpers behind the editor screens.
enum EditorLogic {
    static let legStoryWordLimit = 25
    static let highlightMaxChars = 60
    static let reviewMaxChars = 48

    /// Cut text to `limit` words (blocks typing past the limit).
    static func limitedStory(_ text: String, limit: Int = WordLimit.stopStory) -> String {
        WordLimit.truncated(text, to: limit)
    }

    static func limitedChars(_ text: String, max: Int) -> String {
        text.count <= max ? text : String(text.prefix(max))
    }

    enum CounterState: Equatable { case normal, atLimit }
    static func counterState(_ text: String, limit: Int = WordLimit.stopStory) -> CounterState {
        WordLimit.count(text) >= limit ? .atLimit : .normal
    }
    static func counterText(_ text: String, limit: Int = WordLimit.stopStory) -> String {
        "\(min(WordLimit.count(text), limit)) / \(limit)"
    }

    /// Legs carrying user content that would be lost if `stop` were deleted from `ordered`.
    @MainActor
    static func legsLost(deleting stop: Stop, from ordered: [Stop]) -> [Leg] {
        let remaining = ordered.filter { $0 !== stop }
        var lost = LegSync.legsLost(whenOrderBecomes: remaining)
        if let out = stop.outgoingLeg, out.hasContent, !lost.contains(where: { $0 === out }) { lost.append(out) }
        return lost
    }

    @MainActor
    static func needsDeleteConfirmation(deleting stop: Stop, from ordered: [Stop]) -> Bool {
        !legsLost(deleting: stop, from: ordered).isEmpty
    }

    /// Legs lost by moving `from` to `to` (List.onMove semantics).
    @MainActor
    static func legsLost(moving from: IndexSet, to: Int, in ordered: [Stop]) -> [Leg] {
        var list = ordered
        list.move(fromOffsets: from, toOffset: to)
        return LegSync.legsLost(whenOrderBecomes: list)
    }

    /// Whole minutes >= 0; empty/invalid -> nil.
    static func parseMinutes(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let v = Int(t), v >= 0 else { return nil }
        return min(v, 24 * 60)
    }

    /// Normalises typed numbers: "12,5" is a decimal comma, "1,240" / "1,24,000" / "1,240.50" use commas as thousands separators.
    static func normalizeNumber(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.contains(",") else { return t }
        if t.contains(".") { return t.replacingOccurrences(of: ",", with: "") }      // "1,240.50"
        let parts = t.split(separator: ",", omittingEmptySubsequences: false)
        if parts.count == 2, let frac = parts.last, frac.count != 3 {                  // "12,5" "0,75"
            return t.replacingOccurrences(of: ",", with: ".")
        }
        return t.replacingOccurrences(of: ",", with: "")                               // "1,240" "1,24,000"
    }

    /// Decimal kilometres (accepts comma decimal or grouped digits); empty/invalid/negative -> nil.
    static func parseKm(_ text: String) -> Double? {
        let t = normalizeNumber(text)
        guard !t.isEmpty, let v = Double(t), v >= 0, v.isFinite else { return nil }
        return v
    }

    static func parseAmount(_ text: String) -> Decimal? {
        let t = normalizeNumber(text)
        guard !t.isEmpty, let v = Decimal(string: t), v >= 0 else { return nil }
        return v
    }

    static func formatKm(_ km: Double) -> String {
        km == km.rounded() ? String(Int(km)) : String(format: "%.1f", km)
    }

    static func formatMinutes(_ m: Int) -> String {
        m >= 60 ? (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min") : "\(m) min"
    }

    static func modeName(_ m: TransportMode) -> String {
        switch m {
        case .walk: "Walk"
        case .autoRickshaw: "Auto-rickshaw"
        case .taxi: "Taxi"
        case .bus: "Bus"
        case .localTrain: "Local train"
        case .metro: "Metro"
        case .bike: "Bike"
        case .ferry: "Ferry"
        }
    }

    /// "taxi · 18 min · 5.2 km", or nil when the leg has nothing to show.
    static func legSummary(_ leg: Leg) -> String? {
        var parts: [String] = []
        if leg.modeWasChosen { parts.append(modeName(leg.mode).lowercased()) }
        if let m = leg.durationMinutes { parts.append(formatMinutes(m)) }
        if let k = leg.distanceKm { parts.append("\(formatKm(k)) km") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func kraft(_ c: StopCategory) -> KraftCategory {
        KraftCategory(rawValue: c.rawValue) ?? .other
    }

    static func categoryName(_ c: StopCategory) -> String { c.rawValue.capitalized }

    static let currencies: [(code: String, symbol: String)] = [
        ("INR", "₹"), ("USD", "$"), ("EUR", "€"), ("GBP", "£"), ("JPY", "¥"), ("AED", "AED")
    ]
    static func symbol(for code: String) -> String { currencies.first { $0.code == code }?.symbol ?? code }
    static let defaultCurrency = "INR"

    static func canSave(placeName: String) -> Bool {
        !placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
