import SwiftUI

/// Every DesignSystem component on PaperBackground. Preview/debug only.
struct KraftGallery: View {
    init() { KraftFonts.register() }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Vintage Kraft").font(KraftFont.title())
                        .foregroundStyle(KraftColor.ink)
                    Text("Components · gallery").stampLabel().foregroundStyle(KraftColor.inkSoft)

                    colours
                    HStack(alignment: .top, spacing: 20) {
                        Polaroid(photo: nil, caption: "Gateway of India", width: 180, seed: "g1")
                        VStack(spacing: 28) {
                            TapedPhoto(photo: nil, size: CGSize(width: 110, height: 82), tapes: 2, seed: "g2")
                            PaperClip()
                        }
                    }
                    .padding(.vertical, 8)
                    HStack(spacing: 10) { ForEach(WashiVariant.allCases, id: \.rawValue) { WashiTape(variant: $0) } }

                    ForEach(0..<3, id: \.self) { v in
                        StoryNoteCard(text: "Torn edge variant \(v). We wandered the market until the lamps came on, bargaining for brass bells and tasting every sweet in sight.", variant: v, seed: "n\(v)")
                    }
                    HighlightStrip(text: "Best dosa ever!", seed: "h", showsArrow: true)
                    PlaceTicket(number: 3, name: "Siddhivinayak Temple", category: .temple, arrived: "12:40", spentMinutes: 45)
                    HStack(spacing: 24) {
                        Postmark()
                        Postmark(top: "ARRIVED · 19 OCT 2026", bottom: "MUMBAI", center: "ARRIVED", size: 110)
                    }
                    HStack(spacing: 24) {
                        RatingStamp(rating: 4, review: "Worth the queue")
                        WaxSeal(glyph: "T")
                    }
                    LegConnector(mode: .taxi, minutes: 18, km: 5.2)
                    StatsStrip(stops: 4, km: 8.4, minutes: 320, modes: [.walk, .taxi])
                    icons
                }
                .padding(24)
            }
        }
        .kraftTheme(.phone)
    }

    private var colours: some View {
        let swatches: [(String, Color)] = [("paper", KraftColor.paper), ("paperDeep", KraftColor.paperDeep), ("kraft", KraftColor.kraft),
            ("kraftDark", KraftColor.kraftDark), ("ink", KraftColor.ink), ("inkSoft", KraftColor.inkSoft), ("route", KraftColor.route),
            ("sealRose", KraftColor.sealRose), ("stampTeal", KraftColor.stampTeal), ("highlight", KraftColor.highlight)]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(swatches, id: \.0) { s in
                    RoundedRectangle(cornerRadius: 4).fill(s.1).frame(height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(KraftColor.kraftDark.opacity(0.3), lineWidth: 0.5))
                }
            }
            Text("Allura 44 / 30").font(KraftFont.stopName()).foregroundStyle(KraftColor.ink)
            Text("Lora 16 on 24pt lines, the body face for stories.").storyBody().foregroundStyle(KraftColor.ink)
            Text("Caveat 18 for handwritten notes").font(KraftFont.note()).foregroundStyle(KraftColor.inkSoft)
            Text("Special Elite stamp label").stampLabel().foregroundStyle(KraftColor.stampTeal)
        }
    }

    private var icons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) { ForEach(KraftCategory.allCases) { CategoryIcon(category: $0, size: 34) } }
            HStack(spacing: 8) { ForEach(KraftTransport.allCases) { TransportIcon(mode: $0, size: 32) } }
        }
    }
}

#Preview("KraftGallery") {
    KraftGallery()
}
