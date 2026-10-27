import SwiftUI

/// Hand-built sample page models (all templates, with and without legs). Used by the gallery, previews and tests.
nonisolated enum StoryPageSamples {
    static let storyShort = "We reached the terminal just after sunrise and the whole building glowed orange. A chai vendor pointed us toward the best dosa in town, and we ate it standing up, watching the first trains roll out."

    /// Exactly 100 words.
    static let story100: String = {
        let base = "We reached the terminal just after sunrise and the whole building glowed orange while commuters streamed past carrying tiffin boxes and newspapers. A chai vendor pointed us toward the best dosa in town, so we followed the smell down a narrow lane, ate standing up, and watched the first trains roll out of the station. Later a stranger drew us a tiny map on a paper napkin, promising that the next stop would be even better, and honestly he was right about every single turn along the way until we finally arrived somewhere quiet"
        let words = base.split(separator: " ").prefix(100)
        return words.joined(separator: " ")
    }()

    /// 100 words of ~7 letters (about 800 characters, above the editor's 700 character cap): a deliberately harsh note card case.
    static let worstCase100: String = (0..<100).map { ["journey", "markets", "station", "lantern", "crowded", "morning"][$0 % 6] }.joined(separator: " ")

    static func photos(_ stop: String, _ n: Int) -> [StoryPhoto] {
        (0..<n).map { StoryPhoto(id: "\(stop)-p\($0 + 1)", isHero: $0 == 0) }
    }

    static let leg = StoryLeg(id: "leg-1", modeRaw: "taxi", km: 5.2, minutes: 18,
                              story: "Bumpy ride, loud horns, and a driver who sang old film songs the entire way.")

    static func stop(_ template: StopTemplate, index: Int = 1, total: Int = 4, story: String? = nil, withLegs: Bool = true,
                     seal: Bool = false, rating: Int? = 4, highlight: String? = "Best dosa ever!") -> StopPageModel {
        let id = "stop-\(template.rawValue)-\(index)"
        let first = index == 0, last = index == total - 1
        return StopPageModel(
            id: id, stopID: "00000000-0000-0000-0000-00000000000\(template.rawValue + 1)", index: index, total: total,
            name: ["Café Churchgate", "Gateway of India", "Sardar Pav Bhaji", "Siddhivinayak Temple", "Marine Drive"][template.rawValue],
            story: story ?? storyShort, highlight: highlight, rating: rating, review: rating == nil ? nil : "Worth the queue",
            categoryRaw: ["food", "landmark", "food", "temple", "nature"][template.rawValue],
            arrival: Date(timeIntervalSince1970: 1_792_400_400), spentMinutes: 45, costText: "₹180",
            photos: photos(id, template.rawValue), template: template, seed: UInt64(template.rawValue) &* 7919 &+ 13,
            entry: first ? nil : RoutePoint(edge: .left, t: 0.9),
            exit: last ? nil : RoutePoint(edge: .right, t: 0.9),
            inLeg: first || !withLegs ? nil : leg,
            outLeg: last || !withLegs ? nil : leg,
            hasSeal: seal)
    }

    static let stats = StatsModel(stops: 4, km: 8.4, totalMinutes: 320, travelMinutes: 62, modes: ["walk", "taxi"], photos: 9, moneyText: "₹1,240")

    static let cover = CoverModel(title: "A Day in Mumbai", dateText: "19 OCT 2026", city: "Mumbai",
                                  postmark: "ARRIVED · 19 OCT 2026 · MUMBAI", heroPhotos: photos("cover", 3),
                                  intro: "One day, four stops, too much butter.", seed: 42)

    static let closing = ClosingModel(stats: stats, closingNote: "Mumbai never sleeps, but I did. Home with sticky fingers, a full camera roll and a promise to come back for the vada pav.", seed: 7)

    static let overview = OverviewModel(stops: [OverviewStop(id: "stop-1", number: 1, name: "Café Churchgate", latitude: 18.93, longitude: 72.83)],
                                        legs: [], stats: stats)

    /// Every page type, labelled, in book order.
    static var all: [(label: String, page: StoryPage)] {
        var out: [(label: String, page: StoryPage)] = [("Cover", .cover(cover)), ("Overview (placeholder)", .overview(overview))]
        for t in [StopTemplate.t0, .t1, .t2, .t3, .t4] {
            out.append(("Stop T\(t.rawValue), legs", .stop(stop(t, story: story100, seal: t == .t0 || t == .t1))))
            out.append(("Stop T\(t.rawValue), no legs, last", .stop(stop(t, index: 3, story: storyShort, withLegs: false, rating: nil, highlight: nil))))
        }
        out.append(("Closing", .closing(closing)))
        return out
    }
}

/// Preview-only: every page type at phone size (390x844) and A4 (595x842) side by side.
struct StoryPagesGallery: View {
    static let phoneSize = CGSize(width: 390, height: 844)

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(StoryPageSamples.all.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.label).font(.caption.monospaced())
                        HStack(alignment: .top, spacing: 24) {
                            StoryPageView(page: item.page, metrics: .phone(Self.phoneSize),
                                          callbacks: StoryPageCallbacks(onPhotoTap: { _ in }, onLegTap: { _ in }, onEdit: { _ in }))
                                .frame(width: Self.phoneSize.width, height: Self.phoneSize.height)
                                .shadow(radius: 4)
                            StoryPageView(page: item.page, metrics: .a4)
                                .frame(width: PageMetrics.a4.size.width, height: PageMetrics.a4.size.height)
                                .shadow(radius: 4)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(white: 0.85))
        .environment(\.storyImageProvider, PlaceholderImageProvider())
    }
}

#Preview("Gallery") { StoryPagesGallery() }

#Preview("Stop T4 A4") {
    StoryPageView(page: .stop(StoryPageSamples.stop(.t4, story: StoryPageSamples.story100)), metrics: .a4)
        .environment(\.storyImageProvider, PlaceholderImageProvider())
}

#Preview("Stop T3 phone") {
    StoryPageView(page: .stop(StoryPageSamples.stop(.t3, story: StoryPageSamples.story100)),
                  metrics: .phone(CGSize(width: 390, height: 844)),
                  callbacks: StoryPageCallbacks(onPhotoTap: { _ in }, onLegTap: { _ in }, onEdit: { _ in }))
        .environment(\.storyImageProvider, PlaceholderImageProvider())
}

#Preview("Cover + Closing") {
    HStack {
        StoryPageView(page: .cover(StoryPageSamples.cover), metrics: .a4)
        StoryPageView(page: .closing(StoryPageSamples.closing), metrics: .a4)
    }
    .environment(\.storyImageProvider, PlaceholderImageProvider())
}
