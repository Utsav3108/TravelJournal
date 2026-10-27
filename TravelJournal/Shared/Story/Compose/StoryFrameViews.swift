import SwiftUI

// Cover and closing frames for Story output. The A4 cover and closing pages centre their content on a tall page and
// print the title, the intro card and the brand stamp where Instagram's own UI covers a Story, so Story frames lay the
// same pieces out inside `spec.safeContentRect` instead.

/// Frames for the Story cover: title and date line, then a collage (hero polaroid + up to two taped photos), then the intro.
nonisolated struct StoryCoverLayout {
    var title: CGRect
    var date: CGRect
    var hero: CGRect?
    var taped: [CGRect]
    var kraftBlock: CGRect?
    var intro: CGRect?
    var introText: String

    static func make(_ m: CoverModel, spec: OutputSpec) -> StoryCoverLayout {
        let S = spec.safeContentRect, cw = S.width
        let oneLine = PageText.width(m.title, fontName: "Allura-Regular", size: 44) <= cw
        let title = CGRect(x: S.minX, y: S.minY, width: cw, height: oneLine ? 62 : 104)
        let date = CGRect(x: S.minX, y: title.maxY + 2, width: cw, height: 20)

        var intro: CGRect?
        var introText = ""
        if let t = m.intro, !t.isEmpty {
            introText = StoryTrim.clamp(StoryTrim.trimmed(t), fontName: PageFont.lora, size: StopLayout.storyFontSize,
                                        lineSpacing: StopLayout.storyLineSpacing, width: cw - 32, maxLines: 3)
            let h = PageText.height(introText, fontName: PageFont.lora, size: StopLayout.storyFontSize,
                                    lineSpacing: StopLayout.storyLineSpacing, width: cw - 32) + 32 + 4
            intro = CGRect(x: S.minX, y: S.maxY - h - 4, width: cw, height: h)
        }
        let top = date.maxY + 14
        let bottom = (intro?.minY ?? S.maxY) - 14
        let avail = max(bottom - top, 60)
        let n = min(m.heroPhotos.count, 3)
        guard n > 0 else {
            return StoryCoverLayout(title: title, date: date, hero: nil, taped: [],
                                    kraftBlock: CGRect(x: S.minX, y: top, width: cw, height: avail), intro: intro,
                                    introText: introText)
        }
        let pw = min(190, avail / 1.17, cw * 0.6)
        let ph = pw * 1.17
        let hero = CGRect(x: S.minX + 6, y: top + (avail - ph) / 2, width: pw, height: ph)
        var taped: [CGRect] = []
        if n >= 2 {
            let colX = hero.maxX + 14, colW = S.maxX - colX
            let k = n - 1, gap: CGFloat = 10
            let outerH = (ph - CGFloat(k - 1) * gap) / CGFloat(k)
            let outerW = min(colW, (outerH - 8) / 0.74 + 8)
            taped = (0..<k).map { j in
                CGRect(x: colX + (colW - outerW) / 2, y: hero.minY + CGFloat(j) * (outerH + gap), width: outerW, height: outerH)
            }
        }
        return StoryCoverLayout(title: title, date: date, hero: hero, taped: taped, kraftBlock: nil, intro: intro,
                                introText: introText)
    }

    private init(title: CGRect, date: CGRect, hero: CGRect?, taped: [CGRect], kraftBlock: CGRect?, intro: CGRect?,
                 introText: String) {
        self.title = title
        self.date = date
        self.hero = hero
        self.taped = taped
        self.kraftBlock = kraftBlock
        self.intro = intro
        self.introText = introText
    }
}

struct StoryCoverFrame: View {
    var model: CoverModel
    var spec: OutputSpec

    @Environment(\.storyImageProvider) private var provider
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let L = StoryCoverLayout.make(model, spec: spec)
        let loader = StoryPhotoLoader(provider: provider, interactive: false, displayScale: displayScale)
        let photos = Array(model.heroPhotos.prefix(3))
        let meta = [model.dateText, model.city?.uppercased()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        ZStack(alignment: .topLeading) {
            if let kb = L.kraftBlock {
                Rectangle().fill(KraftColor.kraft.opacity(0.55))
                    .overlay(Rectangle().stroke(KraftColor.kraftDark.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
                    .placed(kb)
            }
            if let hero = L.hero, let p = photos.first {
                Polaroid(photo: loader.image(p, label: model.city ?? "Photo", points: hero.width), caption: model.city ?? "",
                         width: hero.width, seed: "cover/photo/\(p.id)")
                    .placed(hero)
            }
            ForEach(Array(L.taped.enumerated()), id: \.offset) { i, rect in
                if i + 1 < photos.count {
                    let p = photos[i + 1]
                    TapedPhoto(photo: loader.image(p, points: rect.width), size: CGSize(width: rect.width - 8, height: rect.height - 8),
                               tapes: i == 0 ? 2 : 1, seed: "cover/photo/\(p.id)")
                        .placed(rect)
                }
            }
            Text(model.title)
                .font(KraftFont.title(44))
                .foregroundStyle(KraftColor.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .placed(L.title, alignment: .topLeading)
            Text(meta).stampLabel().foregroundStyle(KraftColor.inkSoft).lineLimit(1)
                .placed(L.date, alignment: .leading)
            if let r = L.intro {
                NoteCard(variant: 1, seed: "cover/\(model.seed)/intro", inset: 16) {
                    Text(L.introText).storyBody().foregroundStyle(KraftColor.ink).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: r.width, height: r.height, alignment: .topLeading)
                .placed(r, alignment: .topLeading)
            }
        }
        .frame(width: spec.sliceSize.width, height: spec.sliceSize.height, alignment: .topLeading)
        .background(PaperBackground())
        .clipped()
    }
}

/// Frames for the Story closing page: heading, five stat tiles, the closing note, and (when printed) the brand stamp at the
/// foot of the safe area, clear of Instagram's reply bar.
nonisolated struct StoryClosingLayout {
    var heading: CGRect
    var seal: CGRect
    var tiles: [CGRect]
    var card: CGRect?
    var noteText: String
    var stamp: CGRect?

    static func make(_ m: ClosingModel, spec: OutputSpec, showsStamp: Bool) -> StoryClosingLayout {
        let S = spec.safeContentRect, cw = S.width
        let gap: CGFloat = 10, tileH: CGFloat = 76
        let tileW = (cw - 2 * gap) / 3
        var noteText = ""
        var cardH: CGFloat = 0
        if let t = m.closingNote, !t.isEmpty {
            noteText = StoryTrim.clamp(StoryTrim.trimmed(t), fontName: PageFont.lora, size: StopLayout.storyFontSize,
                                       lineSpacing: StopLayout.storyLineSpacing, width: cw - 36, maxLines: 3)
            cardH = PageText.height(noteText, fontName: PageFont.lora, size: StopLayout.storyFontSize,
                                    lineSpacing: StopLayout.storyLineSpacing, width: cw - 36) + 36 + 4
        }
        let stampSize = MadeWithStamp.defaultSize
        let stamp = showsStamp
            ? CGRect(x: S.minX + (cw - stampSize.width) / 2, y: S.maxY - stampSize.height - 4, width: stampSize.width,
                     height: stampSize.height)
            : nil
        let headingH: CGFloat = 44, tilesH = tileH * 2 + gap
        let group = headingH + 14 + tilesH + (cardH > 0 ? 16 + cardH : 0)
        let floor = (stamp?.minY ?? S.maxY) - (stamp == nil ? 0 : 14)
        let top = S.minY + max(0, (floor - S.minY - group) / 2)
        let heading = CGRect(x: S.minX, y: top, width: cw - 52, height: headingH)
        let seal = CGRect(x: S.maxX - 44, y: top, width: 44, height: 44)
        let ty = heading.maxY + 14
        let tiles: [CGRect] = (0..<5).map { i in
            let row = i / 3, col = i % 3
            let inRow = row == 0 ? 3 : 2
            let rowW = CGFloat(inRow) * tileW + CGFloat(inRow - 1) * gap
            return CGRect(x: S.minX + (cw - rowW) / 2 + CGFloat(col) * (tileW + gap), y: ty + CGFloat(row) * (tileH + gap),
                          width: tileW, height: tileH)
        }
        let card = cardH > 0 ? CGRect(x: S.minX, y: ty + tilesH + 16, width: cw, height: cardH) : nil
        return StoryClosingLayout(heading: heading, seal: seal, tiles: tiles, card: card, noteText: noteText, stamp: stamp)
    }
}

struct StoryClosingFrame: View {
    var model: ClosingModel
    var spec: OutputSpec
    @Environment(\.exportBrandStamp) private var brandStamp

    var body: some View {
        let stamped = ClosingPage.showsBrandStamp(mode: spec.mode, enabled: brandStamp)
        let L = StoryClosingLayout.make(model, spec: spec, showsStamp: stamped)
        let tiles = ClosingTile.tiles(for: model.stats)
        ZStack(alignment: .topLeading) {
            Text("The day in numbers")
                .font(KraftFont.title(30))
                .foregroundStyle(KraftColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .placed(L.heading, alignment: .leading)
            ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                VStack(spacing: 4) {
                    Text(t.numeral)
                        .font(KraftFont.label(26))
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
            if let r = L.card {
                NoteCard(variant: 2, seed: "closing/\(model.seed)/note", inset: 18) {
                    Text(L.noteText).storyBody().foregroundStyle(KraftColor.ink).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: r.width, height: r.height, alignment: .topLeading)
                .placed(r, alignment: .topLeading)
            }
            WaxSeal(glyph: "T", size: L.seal.width, seed: "closing/\(model.seed)/seal").placed(L.seal)
            if let r = L.stamp {
                MadeWithStamp(size: r.size, seed: "closing/\(model.seed)/made-with").placed(r)
            }
        }
        .frame(width: spec.sliceSize.width, height: spec.sliceSize.height, alignment: .topLeading)
        .background(PaperBackground())
        .clipped()
    }
}
