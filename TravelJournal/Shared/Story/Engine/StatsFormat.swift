import Foundation

/// Stats-time formatting in capitals for tiles and stamp labels. The rules live in `TravelFormat.hours`:
/// nearest half hour (ties up), minutes below 15.
nonisolated enum StatsFormat {
    struct Hours: Equatable {
        var numeral: String   // "5", "2½", "½", "10", "0"
        var unit: String      // "HOURS" / "HOUR" / "MIN"
        var joined: String { "\(numeral) \(unit)" }
    }

    /// 0 -> "0 HOURS"; 1...14 -> "10 MIN"; 15...44 -> "½ HOUR"; 45...74 -> "1 HOUR"; 156 -> "2½ HOURS"; 291 -> "5 HOURS".
    static func hours(minutes: Int) -> Hours {
        let p = TravelFormat.hoursParts(minutes: minutes)
        return Hours(numeral: p.numeral, unit: p.unit.uppercased())
    }

    static func hoursText(minutes: Int) -> String { hours(minutes: minutes).joined }
}
