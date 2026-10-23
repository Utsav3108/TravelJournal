import Foundation
import CoreGraphics

/// Page models built from a (privacy-filtered) `JourneySnapshot`, so composed slices reuse the existing page views and
/// stop components. Pure; mirrors what `StoryLayout` builds from a `Journey` (ids, seeds, money text, seal rule).
nonisolated extension JourneySnapshot {
    /// The one stop that carries a wax seal (`StoryLayout.sealStopIndex`).
    var sealStopIndex: Int? {
        StoryLayout.sealStopIndex(candidates: stops.map {
            (template: StoryLayout.template(forPhotoCount: $0.photos.count), rating: $0.rating)
        })
    }

    /// `StoryLeg` for `legs[i]` (same id scheme as `StoryLayout`: "leg-<uuid>").
    func storyLeg(_ i: Int) -> StoryLeg {
        let l = legs[i]
        return StoryLeg(id: "leg-" + l.id.uuidString, modeRaw: l.mode?.rawValue, km: l.km, minutes: l.minutes, story: l.story)
    }

    /// Stop page model for `stops[i]`, without route crossings (composers own the route).
    func stopPageModel(_ i: Int, sealIndex: Int? = nil) -> StopPageModel {
        let s = stops[i]
        let photos = s.photos.prefix(4).map { StoryPhoto(id: $0.id.uuidString, isHero: $0.isHero) }
        let arrival: Date? = if case .exact(let d)? = s.timeOfDay { d } else { nil }
        return StopPageModel(
            id: "stop-" + s.id.uuidString, stopID: s.id.uuidString, index: i, total: stops.count, name: s.placeName,
            story: s.story, highlight: s.highlight, rating: s.rating, review: s.review,
            categoryRaw: (s.category ?? .other).rawValue, arrival: arrival, spentMinutes: s.timeSpentMinutes,
            costText: s.cost.map { StoryLayout.moneyText([$0.currency: $0.amount], order: [$0.currency]) },
            photos: photos, template: StoryLayout.template(forPhotoCount: photos.count),
            seed: PageSeed.fnv1a(s.id.uuidString), entry: nil, exit: nil,
            inLeg: i > 0 && i - 1 < legs.count ? storyLeg(i - 1) : nil,
            outLeg: i < legs.count ? storyLeg(i) : nil,
            hasSeal: (sealIndex ?? sealStopIndex) == i)
    }

    /// What the ticket and postmark print for the arrival: "08:30" in the journey's time zone, or "MORNING" for a bucket.
    func arrivalText(_ i: Int) -> String? {
        switch stops[i].timeOfDay {
        case .exact(let d)?: PageFormat.time(d, timeZone: timeZone)
        case .bucket(let part)?: part.rawValue.uppercased()
        case nil: nil
        }
    }

    var statsModel: StatsModel {
        var money: [String: Decimal] = [:]
        for c in totals.spent { money[c.currency, default: 0] += c.amount }
        return StatsModel(stops: totals.stops, km: totals.km, totalMinutes: totals.totalMinutes,
                          travelMinutes: totals.travelMinutes, modes: totals.modes.map(\.rawValue), photos: totals.photos,
                          moneyText: money.isEmpty ? nil : StoryLayout.moneyText(money, order: totals.spent.map(\.currency)))
    }

    /// Cover: cover photo first, then each stop's hero, distinct, max 3 (same rule as `StoryLayout`).
    var coverModel: CoverModel {
        var picks: [StoryPhoto] = []
        if let c = coverPhotoID { picks.append(StoryPhoto(id: c.uuidString, isHero: true)) }
        for s in stops {
            if let h = s.hero, !picks.contains(where: { $0.id == h.id.uuidString }) {
                picks.append(StoryPhoto(id: h.id.uuidString, isHero: picks.isEmpty))
            }
        }
        return CoverModel(title: title, dateText: StoryLayout.dateText(date, timeZoneID: timeZoneID), city: city,
                          postmark: postmark, heroPhotos: Array(picks.prefix(3)), intro: introNote,
                          seed: PageSeed.fnv1a("cover|" + id.uuidString))
    }

    var overviewModel: OverviewModel {
        OverviewModel(
            stops: stops.enumerated().map { i, s in
                OverviewStop(id: "stop-" + s.id.uuidString, number: i + 1, name: s.placeName,
                             latitude: s.hasLocation ? s.latitude : nil, longitude: s.hasLocation ? s.longitude : nil)
            },
            legs: legs.indices.map(storyLeg), stats: statsModel)
    }

    var closingModel: ClosingModel {
        ClosingModel(stats: statsModel, closingNote: closingNote, seed: PageSeed.fnv1a("closing|" + id.uuidString))
    }
}
