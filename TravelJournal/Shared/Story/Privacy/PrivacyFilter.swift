import Foundation

/// Applies export privacy to a snapshot. Pure: the same snapshot and settings always give the same result.
/// - drops hidden stops (`ExportPrivacy.isHidden`) and merges the legs either side into one (see `mergedLeg`),
///   keeping `legs.count == max(stops.count - 1, 0)` and `legs[i]` joining `stops[i]` -> `stops[i + 1]`;
///   a hidden first or last stop just loses its one leg;
/// - a cover photo that belonged to a hidden stop is replaced by the first visible hero (same fallback as
///   `Journey.coverPhoto`), or nil, so the hidden stop leaves no trace;
/// - `hideCosts`: every `cost` = nil (and so `totals.spent` is empty);
/// - `hideExactTimes`: `arrivalTime` = nil and `timeOfDay` = `.bucket(...)` in the journey's time zone
///   (stops with no arrival time keep nil);
/// - recomputes `totals` from what is left;
/// - sets `mapMode`.
///
/// `city` and `postmark` are journey-level (the journey's city, or the first stop's coarse city hint) and are left
/// as they are: they name a city, never a stop.
nonisolated enum PrivacyFilter {
    typealias Snapshot = JourneySnapshot
    typealias Leg = JourneySnapshot.LegSnapshot

    static func apply(_ snapshot: Snapshot, _ privacy: ExportPrivacy) -> Snapshot {
        var out = snapshot
        let hidden = snapshot.stops.map(privacy.isHidden)

        // Stops and legs. Legs between two visible stops collect every original leg in between.
        var stops: [Snapshot.StopSnapshot] = []
        var legs: [Leg] = []
        var pending: [Leg] = []   // legs since the last visible stop
        for (i, stop) in snapshot.stops.enumerated() {
            if i > 0, i - 1 < snapshot.legs.count { pending.append(snapshot.legs[i - 1]) }
            guard !hidden[i] else { continue }
            if let last = stops.last, !pending.isEmpty {
                legs.append(mergedLeg(pending, from: last.id, to: stop.id))
            }
            pending = []
            stops.append(stop)
        }

        if privacy.hideCosts {
            for i in stops.indices { stops[i].cost = nil }
        }
        if privacy.hideExactTimes {
            let tz = snapshot.timeZone
            for i in stops.indices {
                stops[i].timeOfDay = stops[i].arrivalTime.map { .bucket(dayPart(for: $0, in: tz)) }
                stops[i].arrivalTime = nil
            }
        }

        // Cover: never a hidden stop's photo.
        let hiddenPhotoIDs = Set(zip(snapshot.stops, hidden).filter(\.1).flatMap { $0.0.photos.map(\.id) })
        if let cover = out.coverPhotoID, hiddenPhotoIDs.contains(cover) {
            out.coverPhotoID = stops.first?.hero?.id ?? stops.lazy.compactMap(\.hero).first?.id
        }

        out.stops = stops
        out.legs = legs
        out.totals = Snapshot.Totals(stops: stops, legs: legs)
        out.mapMode = privacy.mapMode
        return out
    }

    // MARK: Leg merging

    /// One leg standing in for `parts` (consecutive legs whose inner stops were hidden).
    /// - id: the first part's (a leg out of a visible stop, so stable and not a hidden stop's id);
    /// - km / minutes: summed over the parts that have them, nil only when none do;
    /// - mode: from the part with the most minutes among those with a chosen mode (nil minutes count as 0,
    ///   ties go to the earlier part); nil when no part has a mode;
    /// - story: the non-empty stories joined with a blank line; nil when none.
    static func mergedLeg(_ parts: [Leg], from: UUID, to: UUID) -> Leg {
        precondition(!parts.isEmpty)
        if parts.count == 1 {
            var leg = parts[0]
            leg.fromStopID = from; leg.toStopID = to
            return leg
        }
        let kms = parts.compactMap(\.km)
        let mins = parts.compactMap(\.minutes)
        var best: Leg?
        for p in parts where p.mode != nil {
            if best == nil || (p.minutes ?? 0) > (best!.minutes ?? 0) { best = p }
        }
        let stories = parts.compactMap(\.story).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Leg(id: parts[0].id, fromStopID: from, toStopID: to, mode: best?.mode,
                   km: kms.isEmpty ? nil : kms.reduce(0, +),
                   minutes: mins.isEmpty ? nil : mins.reduce(0, +),
                   story: stories.isEmpty ? nil : stories.joined(separator: "\n\n"))
    }

    // MARK: Time buckets

    /// Local hour in `timeZone`: 05:00–11:59 morning, 12:00–16:59 afternoon, 17:00–04:59 evening
    /// (late night reads as the evening before rather than an odd "morning").
    static func dayPart(for date: Date, in timeZone: TimeZone) -> Snapshot.DayPart {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        switch cal.component(.hour, from: date) {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        default: return .evening
        }
    }
}
