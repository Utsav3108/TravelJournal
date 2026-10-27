import SwiftUI

/// Tiles shown on the closing page, in order. Pure so it can be tested.
nonisolated struct ClosingTile: Hashable {
    var numeral: String
    var label: String

    static func tiles(for s: StatsModel) -> [ClosingTile] {
        [ClosingTile(numeral: "\(s.stops)", label: "STOPS"),
         ClosingTile(numeral: PageFormat.numeral(s.km), label: "KM"),
         ClosingTile(numeral: StatsFormat.hours(minutes: s.totalMinutes).numeral,
                     label: StatsFormat.hours(minutes: s.totalMinutes).unit),
         ClosingTile(numeral: s.moneyText ?? "–", label: "SPENT"),
         ClosingTile(numeral: "\(s.photos)", label: "PHOTOS")]
    }
}

nonisolated struct ClosingLayout {
    var heading: CGRect
    var tiles: [CGRect]
    var card: CGRect?
    var seal: CGRect

    static func make(_ m: ClosingModel, metrics: PageMetrics) -> ClosingLayout {
        let W = metrics.size.width, H = metrics.size.height, mg = metrics.margin
        let cw = W - 2 * mg
        let gap: CGFloat = 12
        let tileW = (cw - 2 * gap) / 3
        let tileH: CGFloat = 84
        let inset: CGFloat = 18
        var cardH: CGFloat = 0
        if let t = m.closingNote, !t.isEmpty {
            cardH = PageText.height(t, fontName: PageFont.lora, size: 16, lineSpacing: 3.5, width: cw - 2 * inset) + 2 * inset + 4
        }
        let headingH: CGFloat = 48
        let tilesH = tileH * 2 + gap
        let block = headingH + 28 + tilesH + (cardH > 0 ? 40 + cardH : 0) + 90
        let top = max(mg + 24, (H - block) / 2 - 20)
        let heading = CGRect(x: mg, y: top, width: cw, height: headingH)
        let ty = heading.maxY + 28
        var tiles: [CGRect] = []
        for i in 0..<5 {
            let row = i / 3, col = i % 3
            let inRow = row == 0 ? 3 : 2
            let rowW = CGFloat(inRow) * tileW + CGFloat(inRow - 1) * gap
            let x0 = mg + (cw - rowW) / 2
            tiles.append(CGRect(x: x0 + CGFloat(col) * (tileW + gap), y: ty + CGFloat(row) * (tileH + gap), width: tileW, height: tileH))
        }
        let bottomOfTiles = ty + tilesH
        let card = cardH > 0 ? CGRect(x: mg, y: bottomOfTiles + 40, width: cw, height: cardH) : nil
        let sealY = (card?.maxY ?? bottomOfTiles) + (card == nil ? 40 : -12)
        let seal = CGRect(x: W - mg - 56 - 24, y: sealY, width: 56, height: 56)
        return ClosingLayout(heading: heading, tiles: tiles, card: card, seal: seal)
    }
}

/// "The day in numbers": five typewriter tiles, the closing note and a wax seal.
struct ClosingPage: View {
    var model: ClosingModel
    var metrics: PageMetrics
    /// Interactive only (nil when printing): triggers the shared PDF export flow.
    var onSavePDF: (() -> Void)?
    @Environment(\.exportBrandStamp) private var brandStamp

    var body: some View {
        let L = ClosingLayout.make(model, metrics: metrics)
        let tiles = ClosingTile.tiles(for: model.stats)
        ZStack(alignment: .topLeading) {
            Text("The day in numbers")
                .font(KraftFont.title(30))
                .foregroundStyle(KraftColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .placed(L.heading)
            ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                VStack(spacing: 4) {
                    Text(t.numeral)
                        .font(KraftFont.label(28))
                        .foregroundStyle(KraftColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(t.label).stampLabel().foregroundStyle(KraftColor.inkSoft)
                }
                .padding(.horizontal, 8)
                .frame(width: L.tiles[i].width, height: L.tiles[i].height)
                .background(KraftColor.paperDeep)
                .overlay(Rectangle().stroke(KraftColor.kraftDark, style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
                .rotationEffect(.degrees(PageSeed.rotation(id: "closing/\(model.seed)/tile/\(i)", limit: 2.5)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(t.numeral) \(t.label.lowercased())")
                .placed(L.tiles[i])
            }
            if let r = L.card, let note = model.closingNote {
                NoteCard(variant: 2, seed: "closing/\(model.seed)/note", inset: 18) {
                    Text(note).storyBody().foregroundStyle(KraftColor.ink).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: r.width, height: r.height, alignment: .topLeading)
                .placed(r, alignment: .topLeading)
            }
            WaxSeal(glyph: "T", size: 56, seed: "closing/\(model.seed)/seal").placed(L.seal)
        }
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .topLeading)
        .background(PaperBackground())
        .overlay(alignment: .bottom) {
            if let onSavePDF {
                SavePDFStamp(action: onSavePDF, seed: "closing/\(model.seed)/pdf")
                    .padding(.bottom, 48)
            } else if Self.showsBrandStamp(mode: metrics.mode, enabled: brandStamp) {
                // Printed where the interactive "Save as PDF" stamp sits in the app.
                MadeWithStamp(seed: "closing/\(model.seed)/made-with")
                    .padding(.bottom, 52)
            }
        }
        .clipped()
    }

    /// The brand stamp prints only in print mode (the interactive page shows the Save as PDF stamp there).
    nonisolated static func showsBrandStamp(mode: RenderMode, enabled: Bool) -> Bool {
        enabled && mode == .print
    }
}

extension EnvironmentValues {
    /// Draw `MadeWithStamp` on the printed closing page (`ExportPrivacy.showBrandStamp`). Off unless an exporter sets
    /// it, so renderers that place their own stamp (carousel, Story) never get two.
    @Entry var exportBrandStamp: Bool = false
}

/// Stamp-style "Save as PDF" button for the closing page (interactive only, never printed).
struct SavePDFStamp: View {
    var action: () -> Void
    var seed: String = "savepdf"

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                Text("SAVE AS PDF").stampLabel(13)
            }
            .foregroundStyle(KraftColor.stampTeal)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6).stroke(KraftColor.stampTeal, lineWidth: 2)
                    RoundedRectangle(cornerRadius: 6).stroke(KraftColor.stampTeal.opacity(0.6), lineWidth: 0.8).padding(3.5)
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .seededRotation(seed, limit: 2)
        .accessibilityLabel("Save as PDF")
        .accessibilityHint("Creates a printable PDF of this journey")
        .accessibilityIdentifier("savePDF")
    }
}

// MARK: End marker

/// Where the route finishes on the last stop page: a small flag planted on the route end and a "The End" stamp beside it
/// (the double-ruled stamp style of `RatingStamp` / `SavePDFStamp`). The flag stands `flagInset` in from the leading
/// edge, or from the trailing edge when `flagOnTrailing` (route lane on the right).
struct RouteEndMarker: View {
    var size: CGSize
    var flagOnTrailing = false
    var seed: String = "end"

    static let flagInset: CGFloat = 6

    var body: some View {
        let flagX = flagOnTrailing ? size.width - Self.flagInset : Self.flagInset
        let midY = size.height / 2
        let stampW = size.width - 30
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: flagX, y: midY)); p.addLine(to: CGPoint(x: flagX, y: midY - 26))
            }
            .stroke(KraftColor.route, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            Path { p in
                let dir: CGFloat = flagOnTrailing ? -1 : 1
                p.move(to: CGPoint(x: flagX, y: midY - 26)); p.addLine(to: CGPoint(x: flagX + 15 * dir, y: midY - 21))
                p.addLine(to: CGPoint(x: flagX, y: midY - 16)); p.closeSubpath()
            }
            .fill(KraftColor.route)
            Circle().fill(KraftColor.route).frame(width: 7, height: 7).position(x: flagX, y: midY)
            Text("The End")
                .font(KraftFont.label(20))
                .textCase(.uppercase)
                .tracking(3)
                .foregroundStyle(KraftColor.stampTeal)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: stampW, height: size.height - 16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).stroke(KraftColor.stampTeal, lineWidth: 2)
                        RoundedRectangle(cornerRadius: 6).stroke(KraftColor.stampTeal.opacity(0.6), lineWidth: 0.8).padding(3.5)
                    }
                )
                .opacity(0.9)
                .seededRotation(seed, limit: 3)
                .placed(CGRect(x: flagOnTrailing ? 0 : size.width - stampW, y: 8, width: stampW, height: size.height - 16))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The End")
    }
}
