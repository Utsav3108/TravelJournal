import Foundation

/// What an export leaves out. Global defaults live in `ExportPrivacyDefaults`; a journey may override them
/// (`Journey.exportPrivacy`), and each stop may override the hide rule (`Stop.exportHidden`).
nonisolated struct ExportPrivacy: Codable, Hashable, Sendable {
    nonisolated enum MapMode: String, Codable, Hashable, Sendable, CaseIterable {
        case show, zoomedOut, hidden
    }

    var hideStayStops: Bool = true
    var hideCosts: Bool = false
    var hideExactTimes: Bool = false
    var mapMode: MapMode = .show

    init(hideStayStops: Bool = true, hideCosts: Bool = false, hideExactTimes: Bool = false, mapMode: MapMode = .show) {
        self.hideStayStops = hideStayStops
        self.hideCosts = hideCosts
        self.hideExactTimes = hideExactTimes
        self.mapMode = mapMode
    }

    /// Missing keys (data saved by an older build) keep their defaults; an unknown map mode falls back to `.show`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExportPrivacy()
        hideStayStops = try c.decodeIfPresent(Bool.self, forKey: .hideStayStops) ?? d.hideStayStops
        hideCosts = try c.decodeIfPresent(Bool.self, forKey: .hideCosts) ?? d.hideCosts
        hideExactTimes = try c.decodeIfPresent(Bool.self, forKey: .hideExactTimes) ?? d.hideExactTimes
        mapMode = (try? c.decodeIfPresent(MapMode.self, forKey: .mapMode)) ?? d.mapMode
    }

    // MARK: Stop rule

    /// The per-stop override wins; otherwise Stay stops are hidden when `hideStayStops` is on.
    static func isHidden(exportHidden: Bool?, category: StopCategory?, hideStayStops: Bool) -> Bool {
        exportHidden ?? (hideStayStops && category == .stay)
    }

    func isHidden(_ stop: JourneySnapshot.StopSnapshot) -> Bool {
        Self.isHidden(exportHidden: stop.exportHidden, category: stop.category, hideStayStops: hideStayStops)
    }

    @MainActor
    func isHidden(_ stop: Stop) -> Bool {
        Self.isHidden(exportHidden: stop.exportHidden, category: stop.category, hideStayStops: hideStayStops)
    }

    // MARK: Resolution

    /// The journey's override when it has one, else the global defaults.
    @MainActor
    static func resolved(for journey: Journey, defaults: ExportPrivacyDefaults = .standard) -> ExportPrivacy {
        journey.exportPrivacy ?? defaults.load()
    }
}

extension Journey {
    /// Per-journey override, stored as JSON in `exportPrivacyData`. nil = use the global defaults.
    /// Unreadable data reads as nil (falls back to the defaults).
    var exportPrivacy: ExportPrivacy? {
        get { exportPrivacyData.flatMap { try? JSONDecoder().decode(ExportPrivacy.self, from: $0) } }
        set { exportPrivacyData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

/// Global export privacy defaults, stored as JSON under one UserDefaults key. Inject a suite in tests.
nonisolated struct ExportPrivacyDefaults: @unchecked Sendable {   // UserDefaults is thread-safe
    static let key = "exportPrivacy.defaults"
    static var standard: ExportPrivacyDefaults { ExportPrivacyDefaults(store: .standard) }

    let store: UserDefaults

    init(store: UserDefaults = .standard) { self.store = store }

    /// Saved defaults, or `ExportPrivacy()` when nothing (readable) is saved.
    func load() -> ExportPrivacy {
        store.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ExportPrivacy.self, from: $0) } ?? ExportPrivacy()
    }

    func save(_ privacy: ExportPrivacy) {
        guard let data = try? JSONEncoder().encode(privacy) else { return }
        store.set(data, forKey: Self.key)
    }

    func reset() { store.removeObject(forKey: Self.key) }
}
