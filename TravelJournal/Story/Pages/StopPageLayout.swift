import Foundation
import CoreGraphics

/// Font names duplicated as literals so layout stays nonisolated (verified against KraftFontName by a test).
nonisolated enum PageFont {
    static let lora = "Lora-Regular"
    static let caveat = "CaveatRoman-Regular"
    static let elite = "SpecialElite-Regular"
}

/// Frames (page-relative, unrotated) for every element of a stop page. Pure function of the model and metrics, so
/// phone and A4 share one code path (decision #1: phones reflow from `PageMetrics.size`, they do not scale an A4 canvas).
///
/// A4 (width >= 500) follows the T0-T4 wireframes of component-specs.md: hero polaroid left, ticket / tags / taped photos in
/// the right column, full-width note card under the band, connector slot at the bottom. Narrow pages stack: ticket, hero with
/// taped photos beside it, tags, note card; the page grows (and the interactive view scrolls) when content is taller.
nonisolated struct StopLayout {
    var pageSize: CGSize
    var wide: Bool
    var photoCount: Int
    var hero: CGRect?
    var taped: [CGRect] = []          // outer frames (photo + 4pt border)
    var tapedTapes: Int = 1
    var ticket: CGRect = .zero
    var cost: CGRect?
    var highlight: CGRect?
    var highlightArrow = false
    var rating: CGRect?
    var card: CGRect = .zero
    var cardInset: CGFloat = 16
    var cardClipped = false           // text taller than the room left: view falls back to minimumScaleFactor
    var seal: CGRect?
    var postmark: CGRect?
    var edit: CGRect = .zero
    var slotSize: CGSize = .zero
    var anchor: CGPoint = .zero
    var contentBottom: CGFloat = 0
    var bandScale: CGFloat = 1        // 1, or 0.85 when the photo band had to shrink (tier a)
    var route: RoutePlan

    static let storyFontSize: CGFloat = 16
    static let storyLineSpacing: CGFloat = 3.5

    /// "SPENT 45 MIN · COST ₹180": the time-spent and cost label under the ticket (nil when neither is set).
    static func chipText(_ m: StopPageModel) -> String? {
        var parts: [String] = []
        if let s = m.spentMinutes { parts.append("SPENT \(s) MIN") }
        if let c = m.costText, !c.isEmpty { parts.append("COST \(c)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func ticketRotation(stopID: String) -> Double { PageSeed.rotation(id: "\(stopID)/ticket", limit: 3) }

    static func make(_ m: StopPageModel, metrics: PageMetrics) -> StopLayout {
        let first = build(m, metrics: metrics, bandScale: 1)
        if first.wide, first.cardClipped || first.contentBottom > first.limit(m, metrics) {
            let second = build(m, metrics: metrics, bandScale: 0.85)
            return second
        }
        return first
    }

    private func limit(_ m: StopPageModel, _ metrics: PageMetrics) -> CGFloat {
        metrics.size.height - metrics.margin - (m.exit != nil ? slotSize.height : 0)
    }

    // swiftlint:disable:next function_body_length
    private static func build(_ m: StopPageModel, metrics: PageMetrics, bandScale s: CGFloat) -> StopLayout {
        let W = metrics.size.width, H0 = metrics.size.height, mg = metrics.margin
        let wide = W >= 500
        let cw = W - 2 * mg
        let n = min(m.photos.count, 4)
        let c: CGFloat = wide ? 1 : max(0.8, min(1.4, cw / 342))   // compact scale factor
        let hasExit = m.exit != nil
        let slot = wide ? CGSize(width: 280, height: 100) : CGSize(width: 190 * c, height: 64)
        let gap: CGFloat = 12
        let y0 = mg
        let inset: CGFloat = wide ? 18 : 16
        let ratingH: CGFloat = (m.review?.isEmpty ?? true) ? 64 : 84
        let hasRating = m.rating != nil

        var L = StopLayout(pageSize: metrics.size, wide: wide, photoCount: n, route: RoutePlan(anchor: .zero))
        L.cardInset = inset
        L.slotSize = hasExit ? slot : .zero
        L.bandScale = s

        // Note card height from the real font metrics (+4 safety).
        let textW = cw - 2 * inset
        let storyH = PageText.height(m.story, fontName: PageFont.lora, size: storyFontSize, lineSpacing: storyLineSpacing, width: textW)
        let cardH = max(storyH, 24) + 2 * inset + 4

        // Highlight: measured width and line count for an available width.
        func highlightRect(x: CGFloat, y: CGFloat, avail: CGFloat, arrow: Bool) -> CGRect? {
            guard let h = m.highlight, !h.isEmpty else { return nil }
            let arrowW: CGFloat = arrow ? 46 : 0
            let text = PageText.width(h, fontName: PageFont.caveat, size: 18) + 20
            let oneLine = text + arrowW <= avail
            let w = oneLine ? text + arrowW : avail
            return CGRect(x: x, y: y, width: w, height: oneLine ? 32 : 56)
        }

        // Ticket + cost label (shared by every template).
        let ticketW: CGFloat = wide ? 280 : min(250 * c, cw - 8)
        let ticketH: CGFloat = wide ? 72 : 64
        var cursorY: CGFloat
        let heroX = mg + 4
        let heroW: CGFloat
        switch (wide, n) {
        case (true, 4): heroW = 215 * s
        case (true, _): heroW = 230 * s
        case (false, _): heroW = cw * 0.62
        }
        let heroH = heroW * 1.17

        func costRect(below r: CGRect) -> CGRect? {
            guard let t = chipText(m) else { return nil }
            let w = PageText.width(t, fontName: PageFont.elite, size: 11, tracking: 1.5) + 20
            return CGRect(x: r.minX, y: r.maxY + 8, width: w, height: 22)
        }

        if wide {
            let colX = heroX + heroW + 16
            let colW = W - mg - colX
            if n == 0 {
                L.ticket = CGRect(x: mg + 8, y: y0 + 8, width: ticketW, height: ticketH)
            } else {
                L.ticket = CGRect(x: colX + 8, y: y0 + 8, width: min(ticketW, colW - 8), height: ticketH)
            }
            L.cost = costRect(below: L.ticket)
            cursorY = (L.cost ?? L.ticket).maxY + gap

            var bandBottom: CGFloat = L.ticket.maxY
            if n >= 1 {
                L.hero = CGRect(x: heroX, y: y0 + 4, width: heroW, height: heroH)
                bandBottom = L.hero!.maxY + 8
                L.highlight = highlightRect(x: colX, y: cursorY, avail: colW, arrow: false)
                if let h = L.highlight { cursorY = h.maxY + gap }
                switch n {
                case 1:
                    if hasRating { L.rating = CGRect(x: colX, y: cursorY, width: 150, height: ratingH) }
                case 2:
                    let w = 150 * s, h = 112 * s
                    L.taped = [CGRect(x: colX - 30, y: cursorY, width: w + 8, height: h + 8)]
                    L.tapedTapes = 2
                    bandBottom = max(bandBottom, L.taped[0].maxY)
                case 3:
                    let outerW = (colW - 9) / 2
                    let inner = CGSize(width: outerW - 8, height: (outerW - 8) * 0.74)
                    L.taped = (0..<2).map { i in
                        CGRect(x: colX + CGFloat(i) * (outerW + 9), y: cursorY, width: outerW, height: inner.height + 8)
                    }
                default: // 4: rating in the column; three taped photos in a row under the band
                    if hasRating { L.rating = CGRect(x: colX, y: cursorY, width: 150, height: ratingH) }
                }
                if n == 2 || n == 3, hasRating {
                    let rx = heroX + (heroW - 150) / 2
                    L.rating = CGRect(x: rx, y: L.hero!.maxY + 10, width: 150, height: ratingH)
                }
                bandBottom = max(bandBottom, L.rating?.maxY ?? 0, L.taped.map(\.maxY).max() ?? 0)
                if n == 4 {
                    let outerW = (cw - 24) / 3
                    let h = 100 * s + 8
                    let y = bandBottom + gap
                    L.taped = (0..<3).map { i in CGRect(x: mg + CGFloat(i) * (outerW + 12), y: y, width: outerW, height: h) }
                    bandBottom = y + h
                }
                L.card = CGRect(x: mg, y: bandBottom + gap, width: cw, height: cardH)
                L.contentBottom = L.card.maxY
                if let seal = (m.hasSeal ? CGRect(x: mg + 24, y: L.card.maxY - 12, width: 56, height: 56) : nil) { L.seal = seal }
            } else {
                // T0: ticket, postmark top-right, note card, then highlight / seal / rating row.
                L.postmark = CGRect(x: W - mg - 92, y: y0 + 12, width: 84, height: 84)
                L.card = CGRect(x: mg, y: max((L.cost ?? L.ticket).maxY + 36, y0 + 120), width: cw, height: cardH)
                var rowY = L.card.maxY + 18
                var x = mg + 8
                if m.hasSeal { L.seal = CGRect(x: x + 8, y: rowY, width: 56, height: 56); x += 80 }
                let ratingW: CGFloat = hasRating ? 150 + 12 : 0
                L.highlight = highlightRect(x: x, y: rowY, avail: W - mg - x - ratingW, arrow: false)
                if hasRating { L.rating = CGRect(x: W - mg - 150 - 6, y: rowY, width: 150, height: ratingH) }
                rowY = max(L.seal?.maxY ?? 0, L.highlight?.maxY ?? 0, L.rating?.maxY ?? 0, rowY)
                L.contentBottom = max(L.card.maxY, rowY)
            }
            // Fit: shrink the card to the room that is left rather than run into the connector slot.
            let limit = H0 - mg - (hasExit ? slot.height : 0)
            if n >= 1, L.card.maxY > limit {
                let room = max(limit - L.card.minY, 120)
                if room < cardH { L.card.size.height = room; L.cardClipped = true }
                L.contentBottom = L.card.maxY
            }
            L.pageSize = CGSize(width: W, height: H0)
        } else {
            L.ticket = CGRect(x: mg + 8, y: y0 + 8, width: ticketW, height: ticketH)
            L.cost = costRect(below: L.ticket)
            cursorY = (L.cost ?? L.ticket).maxY + gap
            var tagsInRow = true
            var heroRect: CGRect?
            if n >= 1 {
                let bandTop = cursorY
                let hero = CGRect(x: heroX, y: bandTop, width: heroW, height: heroH)
                heroRect = hero
                L.hero = hero
                var stackBottom = hero.minY
                let rightX = W - mg
                switch n {
                case 2:
                    let w = 112 * c, h = 84 * c
                    L.taped = [CGRect(x: rightX - w - 8, y: bandTop + 8, width: w + 8, height: h + 8)]
                    L.tapedTapes = 2
                case 3:
                    let w = 104 * c, h = 78 * c
                    L.taped = (0..<2).map { i in CGRect(x: rightX - w - 8, y: bandTop + 8 + CGFloat(i) * (h + 18), width: w + 8, height: h + 8) }
                default:
                    if n == 4 {
                        let w = 96 * c, h = 72 * c
                        L.taped = (0..<3).map { i in CGRect(x: rightX - w - 8, y: bandTop + 4 + CGFloat(i) * (h + 16), width: w + 8, height: h + 8) }
                    }
                }
                stackBottom = max(stackBottom, L.taped.map(\.maxY).max() ?? 0)
                var bandBottom = max(hero.maxY, stackBottom)
                if hasRating {
                    let ry = max((L.taped.map(\.maxY).max() ?? bandTop) + 8, hero.maxY - ratingH)
                    let rx = W - mg - 150
                    if ry + ratingH <= bandBottom + 0.5, rx >= hero.maxX - 24 {
                        L.rating = CGRect(x: rx, y: ry, width: 150, height: ratingH)
                        tagsInRow = false
                    }
                }
                _ = bandBottom
                bandBottom += 14
                cursorY = bandBottom
            }
            // Tags row: highlight (left) and the rating when it did not fit beside the hero.
            let ratingInRow = hasRating && L.rating == nil
            let hlAvail = ratingInRow ? cw - 150 - 12 : cw - 8
            if let h = highlightRect(x: mg + 8, y: cursorY, avail: hlAvail, arrow: heroRect != nil) {
                L.highlight = h
                L.highlightArrow = heroRect != nil && h.width + 0 <= hlAvail
            }
            if ratingInRow { L.rating = CGRect(x: W - mg - 150, y: cursorY, width: 150, height: ratingH) }
            _ = tagsInRow
            var rowBottom = cursorY
            if let h = L.highlight { rowBottom = max(rowBottom, h.maxY) }
            if ratingInRow { rowBottom = max(rowBottom, cursorY + ratingH) }
            if L.highlight != nil || ratingInRow { cursorY = rowBottom + gap }
            if n == 0 { cursorY = max(cursorY, L.ticket.maxY + 24) }
            L.card = CGRect(x: mg, y: cursorY, width: cw, height: cardH)
            L.contentBottom = L.card.maxY
            if m.hasSeal { L.seal = CGRect(x: mg + 24, y: L.card.maxY - 12, width: 56, height: 56) }
            L.edit = CGRect(x: W - mg - 36, y: y0 - 4, width: 36, height: 36)
            // The page grows with its content; the interactive view scrolls.
            let bottomPad = (L.seal != nil ? 44.0 : 0.0)
            var pageH = max(H0, L.contentBottom + bottomPad + (hasExit ? slot.height : 0) + mg)
            if hasExit { pageH = max(pageH, L.contentBottom + bottomPad + slot.height + mg) }
            L.pageSize = CGSize(width: W, height: pageH)
        }
        L.edit = CGRect(x: W - mg - 36, y: max(y0 - 4, 4), width: 36, height: 36)

        // Anchor: centre of the numbered pin on the ticket (5,5 from its top-left), rotated with the ticket.
        let tc = CGPoint(x: L.ticket.midX, y: L.ticket.midY)
        let pinRaw = CGPoint(x: L.ticket.minX + 5, y: L.ticket.minY + 5)
        L.anchor = PageRouteGeometry.rotate(pinRaw, around: tc, degrees: ticketRotation(stopID: m.stopID))

        // Exit point: normalised position from the model; pushed below the content (phone only) so the slot never overlaps it.
        var exitOverride: CGPoint?
        if let exit = m.exit {
            var x = PageRouteGeometry.pagePoint(exit, in: L.pageSize)
            if !wide, exit.edge == .left || exit.edge == .right {
                let minY = L.contentBottom + (L.seal != nil ? 44 : 0) + slot.height / 2 + 4
                if x.y < minY {
                    x.y = minY
                    L.pageSize.height = max(L.pageSize.height, x.y + slot.height / 2 + mg / 2)
                }
            }
            exitOverride = x
        }
        L.route = RoutePlan.make(stopID: m.stopID, size: L.pageSize, anchor: L.anchor, entry: m.entry, exit: m.exit,
                                 exitPointOverride: exitOverride, slotSize: slot)
        return L
    }
}
