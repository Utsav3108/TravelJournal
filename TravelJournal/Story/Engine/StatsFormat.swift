import Foundation

/// Shared stats-time formatting: hours only, rounded to the nearest half hour (ties round up).
nonisolated enum StatsFormat {
    struct Hours: Equatable {
        var numeral: String   // "5", "2½", "½", "0"
        var unit: String      // "HOURS" / "HOUR"
        var joined: String { "\(numeral) \(unit)" }
    }

    /// 0 -> "0 HOURS"; 1...44 -> "½ HOUR"; 45...74 -> "1 HOUR"; 156 -> "2½ HOURS"; 291 -> "5 HOURS".
    static func hours(minutes: Int) -> Hours {
        let m = max(0, minutes)
        if m == 0 { return Hours(numeral: "0", unit: "HOURS") }
        let halves = max(1, (m + 15) / 30)   // half-hour units, ties up, at least one
        let whole = halves / 2, half = halves % 2 == 1
        let numeral = whole == 0 ? "½" : "\(whole)" + (half ? "½" : "")
        return Hours(numeral: numeral, unit: halves <= 2 ? "HOUR" : "HOURS")
    }

    static func hoursText(minutes: Int) -> String { hours(minutes: minutes).joined }
}
