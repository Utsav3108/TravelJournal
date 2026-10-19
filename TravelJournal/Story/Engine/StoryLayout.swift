import Foundation

/// Maps a Journey to ordered story pages: cover, overview, one page per stop, closing.
/// Pure decisions (template, seal, money text) are static so tests and views can reuse them.
nonisolated struct StoryLayout: StoryPageBuilding {
    init() {}

    @MainActor
    func pages(for journey: Journey) -> [StoryPage] {
        let stops = journey.orderedStops
        let n = stops.count
        let stats = Self.stats(for: journey)

        // Leg i joins stop i and i+1. Key falls back to the from-stop id if the Leg row is missing.
        let legCount = max(n - 1, 0)
        let legs: [Leg?] = (0..<legCount).map { stops[$0].outgoingLeg }
        let legKeys: [String] = (0..<legCount).map { i in
            "leg-" + (legs[i]?.id ?? stops[i].id).uuidString
        }
        let storyLegs: [StoryLeg] = (0..<legCount).map { Self.storyLeg(legs[$0], key: legKeys[$0]) }
        let crossings = n > 0 ? RouteGeometry.stopCrossings(legKeys: legKeys) : []

        let photoLists = stops.map { Self.storyPhotos(for: $0) }
        let sealIndex = Self.sealStopIndex(candidates: (0..<n).map {
            (template: Self.template(forPhotoCount: photoLists[$0].count), rating: stops[$0].rating)
        })

        var out: [StoryPage] = []
        out.append(.cover(cover(journey, stops: stops)))
        out.append(.overview(OverviewModel(
            stops: stops.enumerated().map { i, s in
                let hasLoc = s.latitude != nil && s.longitude != nil
                return OverviewStop(id: Self.stopPageID(s), number: i + 1, name: s.placeName,
                                    latitude: hasLoc ? s.latitude : nil, longitude: hasLoc ? s.longitude : nil)
            },
            legs: storyLegs, stats: stats)))

        for (i, s) in stops.enumerated() {
            let photos = photoLists[i]
            out.append(.stop(StopPageModel(
                id: Self.stopPageID(s), stopID: s.id.uuidString, index: i, total: n, name: s.placeName,
                story: s.story, highlight: Self.nonEmpty(s.highlight), rating: s.rating,
                review: Self.nonEmpty(s.review),
                categoryRaw: s.categoryRaw ?? StopCategory.other.rawValue,
                arrival: s.arrivalTime, spentMinutes: s.timeSpentMinutes,
                costText: s.cost.map { Self.moneyText([$0.currency: $0.amount], order: [$0.currency]) },
                photos: photos, template: Self.template(forPhotoCount: photos.count),
                seed: Seed.fnv1a(s.id.uuidString),
                entry: crossings[i].entry, exit: crossings[i].exit,
                inLeg: i > 0 ? storyLegs[i - 1] : nil,
                outLeg: i < n - 1 ? storyLegs[i] : nil,
                hasSeal: sealIndex == i)))
        }

        out.append(.closing(ClosingModel(stats: stats, closingNote: Self.nonEmpty(journey.closingNote),
                                         seed: Seed.fnv1a("closing|" + journey.id.uuidString))))
        return out
    }

    // MARK: Pure decisions

    /// Template by photo count (0...4; larger counts clamp to t4).
    static func template(forPhotoCount n: Int) -> StopTemplate {
        StopTemplate(rawValue: min(max(n, 0), 4)) ?? .t4
    }

    /// Wax seal rule (component-specs 1.8 / T0): a stop is eligible when it has no photos (t0) or a
    /// 5-star rating; t4 is never eligible (tightest layout, ~6pt spare). The journey gets ONE seal-bearing
    /// stop page: highest rating wins (unrated = 0), ties go to the earliest stop. Deterministic, so a page
    /// never carries more than one seal and the story is not littered with them. The cover seal is separate.
    static func sealStopIndex(candidates: [(template: StopTemplate, rating: Int?)]) -> Int? {
        var best: (index: Int, score: Int)?
        for (i, c) in candidates.enumerated() {
            guard c.template != .t4, c.template == .t0 || c.rating == 5 else { continue }
            let score = c.rating ?? 0
            if best == nil || score > best!.score { best = (i, score) }
        }
        return best?.index
    }

    @MainActor
    static func stopPageID(_ s: Stop) -> String { "stop-" + s.id.uuidString }

    /// Hero first (isHero else first by order), then the remaining in order; capped at 4.
    @MainActor
    static func storyPhotos(for stop: Stop) -> [StoryPhoto] {
        let ordered = stop.orderedPhotos
        guard !ordered.isEmpty else { return [] }
        let hero = stop.hero ?? ordered[0]
        let rest = ordered.filter { $0 !== hero }
        return ([hero] + rest).prefix(4).map { storyPhoto($0, isHero: $0 === hero) }
    }

    @MainActor
    static func storyPhoto(_ p: StopPhoto, isHero: Bool) -> StoryPhoto {
        StoryPhoto(id: p.id.uuidString, relativePath: p.relativePath,
                   thumbPath: p.thumbRelativePath.isEmpty ? nil : p.thumbRelativePath, isHero: isHero)
    }

    /// Leg without a chosen mode keeps modeRaw nil but still carries km/minutes/story (decision 4).
    @MainActor
    static func storyLeg(_ leg: Leg?, key: String) -> StoryLeg {
        guard let leg else { return StoryLeg(id: key, modeRaw: nil, km: nil, minutes: nil, story: nil) }
        return StoryLeg(id: key, modeRaw: leg.modeWasChosen ? leg.modeRaw : nil,
                        km: leg.distanceKm, minutes: leg.durationMinutes, story: nonEmpty(leg.story))
    }

    @MainActor
    static func stats(for journey: Journey) -> StatsModel {
        let s = JourneyStats(journey: journey)
        var order: [String] = []
        for st in journey.orderedStops { if let c = st.cost?.currency, !order.contains(c) { order.append(c) } }
        return StatsModel(stops: s.stops, km: s.hasKm ? s.km : nil, totalMinutes: s.totalMinutes,
                          travelMinutes: s.travelMinutes, modes: s.modes.map(\.rawValue), photos: s.photos,
                          moneyText: s.money.isEmpty ? nil : moneyText(s.money, order: order))
    }

    /// "₹1,240" or "₹300 + $5": per-currency sums, no conversion, joined in first-use order.
    static func moneyText(_ money: [String: Decimal], order: [String]) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.groupingSize = 3
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        let codes = order.filter { money[$0] != nil } + money.keys.filter { !order.contains($0) }.sorted()
        return codes.map { code in
            let num = f.string(from: (money[code] ?? 0) as NSDecimalNumber) ?? "0"
            if let sym = currencySymbols[code.uppercased()] { return sym + num }
            return "\(code.uppercased()) \(num)"
        }.joined(separator: " + ")
    }

    static let currencySymbols: [String: String] = [
        "INR": "₹", "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "CNY": "¥", "KRW": "₩",
        "AUD": "A$", "CAD": "C$", "THB": "฿", "VND": "₫", "PHP": "₱", "RUB": "₽",
        "TRY": "₺", "ILS": "₪", "NZD": "NZ$", "SGD": "S$", "HKD": "HK$", "MXN": "MX$", "BRL": "R$",
    ]

    static func dateText(_ date: Date, timeZoneID: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        f.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return f.string(from: date).uppercased()
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return s
    }

    /// Cover heroes: cover photo first, then each stop's hero in order; distinct, max 3.
    @MainActor
    private func cover(_ journey: Journey, stops: [Stop]) -> CoverModel {
        var picks: [StopPhoto] = []
        if let c = journey.coverPhoto { picks.append(c) }
        for s in stops { if let h = s.hero, !picks.contains(where: { $0 === h }) { picks.append(h) } }
        return CoverModel(
            title: journey.title, dateText: Self.dateText(journey.date, timeZoneID: journey.timeZoneID),
            city: journey.displayCity, postmark: journey.postmarkText,
            heroPhotos: picks.prefix(3).enumerated().map { Self.storyPhoto($1, isHero: $0 == 0) },
            intro: Self.nonEmpty(journey.introNote), seed: Seed.fnv1a("cover|" + journey.id.uuidString))
    }
}
