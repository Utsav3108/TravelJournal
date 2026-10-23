import Foundation

/// The one place travel numbers and mode names become text. Lower/sentence case; callers that print
/// in capitals (stamp labels, stats tiles) uppercase the result.
///
/// - Stats (totals, travel time) use `hours`: whole and half hours, never "h"/"min" pairs.
/// - A single leg uses `legDuration`: exact and short ("20 min", "1 h 5 min").
/// - Mode names are the short spoken forms ("Auto", "Local train").
nonisolated enum TravelFormat {
    /// Below this, `hours` shows minutes: "½ hour" for a 10-minute walk overstates it.
    static let minutesFallbackBelow = 15

    /// Stats duration, rounded to the nearest half hour (ties round up).
    /// 0 -> "0 hours"; 1...14 -> "10 min"; 15...44 -> "½ hour"; 45...74 -> "1 hour"; 75 -> "1½ hours";
    /// 90 -> "1½ hours"; 156 -> "2½ hours".
    static func hours(minutes: Int) -> String {
        let p = hoursParts(minutes: minutes)
        return "\(p.numeral) \(p.unit)"
    }

    /// `hours` split for tiles that print the number and the unit separately ("2½" / "hours").
    static func hoursParts(minutes: Int) -> (numeral: String, unit: String) {
        let m = max(0, minutes)
        if m == 0 { return ("0", "hours") }
        if m < minutesFallbackBelow { return ("\(m)", "min") }
        let halves = (m + 15) / 30                 // half-hour units, ties up; >= 1 here
        let whole = halves / 2, half = halves % 2 == 1
        let numeral = whole == 0 ? "½" : "\(whole)" + (half ? "½" : "")
        return (numeral, halves <= 2 ? "hour" : "hours")
    }

    /// One leg's time, exact: 45 -> "45 min", 120 -> "2 h", 65 -> "1 h 5 min".
    static func legDuration(minutes: Int) -> String {
        let m = max(0, minutes)
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r) min" }
        if r == 0 { return "\(h) h" }
        return "\(h) h \(r) min"
    }

    /// Short display name: "Walk", "Auto", "Taxi", "Bus", "Local train", "Metro", "Bike", "Ferry".
    static func modeName(_ mode: TransportMode) -> String {
        switch mode {
        case .walk: "Walk"
        case .autoRickshaw: "Auto"
        case .taxi: "Taxi"
        case .bus: "Bus"
        case .localTrain: "Local train"
        case .metro: "Metro"
        case .bike: "Bike"
        case .ferry: "Ferry"
        }
    }

    /// Name for a stored raw value: a `TransportMode` raw ("autoRickshaw") or a legacy `KraftTransport`
    /// raw ("auto-rickshaw", "train"). Nil when absent or unknown.
    static func modeName(raw: String?) -> String? {
        guard let raw else { return nil }
        if let m = TransportMode(rawValue: raw) { return modeName(m) }
        switch raw {
        case "auto-rickshaw": return modeName(.autoRickshaw)
        case "train": return modeName(.localTrain)
        default: return nil
        }
    }

    /// "Taxi, Auto, Walk" (max `limit`, then "+N"); unknown raws are skipped. Nil when nothing to show.
    static func modeList(raws: [String], limit: Int = 3) -> String? {
        let names = raws.compactMap { modeName(raw: $0) }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(limit).joined(separator: ", ")
        return names.count > limit ? "\(shown) +\(names.count - limit)" : shown
    }

    /// One decimal, trailing ".0" dropped: 6.0 -> "6 km", 8.46 -> "8.5 km". A positive distance never shows as 0.
    static func km(_ km: Double) -> String {
        var r = (max(0, km) * 10).rounded() / 10
        if km > 0 && r == 0 { r = 0.1 }
        return (r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) + " km"
    }
}
