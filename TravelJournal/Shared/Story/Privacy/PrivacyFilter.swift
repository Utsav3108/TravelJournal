import Foundation

/// Applies export privacy to a snapshot. Pure. Contract (implemented in Wave 2):
/// - drops hidden stops (`ExportPrivacy.isHidden`) and merges the legs either side into one (km and minutes summed,
///   mode from the longer leg, stories joined), keeping `legs.count == max(stops.count - 1, 0)`;
/// - recomputes `totals`;
/// - `hideCosts`: every `cost` = nil (and so `totals.spent` is empty);
/// - `hideExactTimes`: `arrivalTime` = nil and `timeOfDay` = `.bucket(...)` in the journey's time zone;
/// - sets `mapMode`.
nonisolated enum PrivacyFilter {
    static func apply(_ snapshot: JourneySnapshot, _ privacy: ExportPrivacy) -> JourneySnapshot {
        snapshot   // stub: Wave 2 (agent B)
    }
}
