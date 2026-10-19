import SwiftUI

/// Frames for the cover collage. The collage keeps the A4 proportions (scaled by width) and is centred in the room
/// between the title block and the intro card, so tall phone pages do not leave a hole.
nonisolated struct CoverLayout {
    var title: CGRect
    var date: CGRect
    var hero: CGRect?
    var taped: [CGRect]
    var kraftBlock: CGRect?
    var postmark: CGRect
    var seal: CGRect
    var intro: CGRect?
    var clip: CGRect

    static func make(_ m: CoverModel, metrics: PageMetrics) -> CoverLayout {
        let W = metrics.size.width, H = metrics.size.height, mg = metrics.margin
        let cw = W - 2 * mg
        let s = min(1, cw / 523)
        let n = min(m.heroPhotos.count, 3)

        let titleW = cw - 50 * s - 12
        let oneLine = PageText.width(m.title, fontName: "Allura-Regular", size: 44) <= titleW
        let title = CGRect(x: mg + 50 * s + 6, y: mg + 24, width: titleW, height: oneLine ? 62 : 112)
        let date = CGRect(x: title.minX, y: title.maxY + 2, width: title.width, height: 20)

        var intro: CGRect?
        var introTop = H - mg
        if let t = m.intro, !t.isEmpty {
            let h = PageText.height(t, fontName: PageFont.lora, size: 16, lineSpacing: 3.5, width: cw - 32) + 32 + 4
            intro = CGRect(x: mg, y: H - mg - h - 4, width: cw, height: h)
            introTop = intro!.minY
        }

        let ctMin = date.maxY + 24
        let pw = 300 * s
        let ph = pw * 1.17
        let pmSize = 120 * s
        var hero: CGRect?
        var taped: [CGRect] = []
        var kraft: CGRect?
        var groupH: CGFloat
        let tw = 198 * s, th = 208 * s
        if n == 0 {
            groupH = 300 * s
        } else {
            groupH = ph + 24 * s + pmSize
            if n >= 2 { groupH = max(groupH, 2 * th + 10 * s + 20 * s) }
            if n == 2 { groupH = max(groupH, ph + 24 * s + pmSize) }
        }
        let avail = introTop - 16 - ctMin
        let ct = ctMin + max(0, (avail - groupH) / 2)

        if n == 0 {
            kraft = CGRect(x: mg, y: ct, width: cw, height: groupH)
        } else {
            hero = CGRect(x: mg + 6, y: ct, width: pw, height: ph)
            if n >= 2 { taped.append(CGRect(x: mg + cw - tw, y: ct + 10 * s, width: tw, height: th)) }
            if n >= 3 { taped.append(CGRect(x: mg + cw - tw - 6 * s, y: ct + 10 * s + th + 10 * s, width: tw, height: th)) }
        }
        let pmY = n == 0 ? ct + groupH / 2 - pmSize / 2 : ct + ph + 24 * s
        let pmX = n == 0 ? mg + cw / 2 - pmSize / 2 - 30 : mg + 14 * s
        let postmark = CGRect(x: pmX, y: pmY, width: pmSize, height: pmSize)
        let seal = CGRect(x: postmark.maxX + 30 * s + (n == 0 ? 40 : 0), y: postmark.midY - 28 + 6, width: 56, height: 56)
        return CoverLayout(title: title, date: date, hero: hero, taped: taped, kraftBlock: kraft, postmark: postmark,
                           seal: seal, intro: intro, clip: CGRect(x: mg + 4, y: mg - 8, width: 24, height: 54))
    }
}

struct CoverPage: View {
    var model: CoverModel
    var metrics: PageMetrics

    @Environment(\.storyImageProvider) private var provider

    var body: some View {
        let L = CoverLayout.make(model, metrics: metrics)
        let loader = StoryPhotoLoader(provider: provider, interactive: metrics.mode == .interactive)
        let photos = Array(model.heroPhotos.prefix(3))
        let parts = PageFormat.postmarkParts(model.postmark)
        let meta = [model.dateText, model.city?.uppercased()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        ZStack(alignment: .topLeading) {
            if let kb = L.kraftBlock {
                Rectangle().fill(KraftColor.kraft.opacity(0.55))
                    .overlay(Rectangle().stroke(KraftColor.kraftDark.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
                    .placed(kb)
            }
            if let hero = L.hero, let p = photos.first {
                Polaroid(photo: loader.image(p), caption: model.city ?? "", width: hero.width, seed: "cover/photo/\(p.id)")
                    .placed(hero)
            }
            ForEach(Array(L.taped.enumerated()), id: \.offset) { i, rect in
                if i + 1 < photos.count {
                    let p = photos[i + 1]
                    TapedPhoto(photo: loader.image(p), size: CGSize(width: rect.width - 8, height: rect.height - 8),
                               tapes: i == 0 ? 2 : 1, seed: "cover/photo/\(p.id)")
                        .placed(rect)
                }
            }
            Text(model.title)
                .font(KraftFont.title(44))
                .foregroundStyle(KraftColor.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
                .placed(L.title, alignment: .topLeading)
            Text(meta).stampLabel().foregroundStyle(KraftColor.inkSoft).lineLimit(1)
                .placed(L.date, alignment: .leading)
            PaperClip(height: L.clip.height).placed(L.clip)
            StoryPostmark(top: parts.top, bottom: parts.bottom, center: parts.center, size: L.postmark.width,
                          seed: "cover/\(model.seed)/postmark")
                .placed(L.postmark)
            WaxSeal(glyph: String(model.title.first.map { String($0).uppercased() } ?? "T"), size: 56, seed: "cover/\(model.seed)/seal")
                .placed(L.seal)
            if let r = L.intro, let t = model.intro {
                NoteCard(variant: 1, seed: "cover/\(model.seed)/intro", inset: 16) {
                    Text(t).storyBody().foregroundStyle(KraftColor.ink).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: r.width, height: r.height, alignment: .topLeading)
                .placed(r, alignment: .topLeading)
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .topLeading)
        .background(PaperBackground())
        .clipped()
    }
}
