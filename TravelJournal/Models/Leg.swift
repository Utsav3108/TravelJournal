import Foundation
import SwiftData

/// Leg from stop N to stop N+1.
@Model
final class Leg {
    var id: UUID = UUID()
    var fromStop: Stop?
    var toStop: Stop?
    var modeRaw: String = TransportMode.walk.rawValue
    /// False until the user picks a mode (connector then shows distance/time only).
    var modeWasChosen: Bool = false
    var distanceKm: Double?
    var durationMinutes: Int?
    var story: String?

    init(from: Stop? = nil, to: Stop? = nil) {
        self.fromStop = from
        self.toStop = to
    }

    var mode: TransportMode {
        get { TransportMode(storedRaw: modeRaw) }
        set { modeRaw = newValue.rawValue; modeWasChosen = true }
    }

    var hasContent: Bool {
        (story?.isEmpty == false) || distanceKm != nil || durationMinutes != nil || modeWasChosen
    }
}
