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

    /// `entryY`: absolute y (page points) where the previous page's route exits; this page's entry must meet it so the
    /// dashed line is continuous across the seam. nil = fall back to `entry.t * pageHeight` (first page / unknown neighbour).
    static func make(_ m: StopPageModel, metrics: PageMetrics, entryY: CGFloat? = nil) -> StopLayout {
        let first = build(m, metrics: metrics, bandScale: 1, entryY: entryY)
        if first.wide, first.cardClipped || first.contentBottom > first.limit(m, metrics) {
            let second = build(m, metrics: metrics, bandScale: 0.85, entryY: entryY)
            return second
        }
        return first
    }

    private func limit(_ m: StopPageModel, _ metrics: PageMetrics) -> CGFloat {
        metrics.size.height - metrics.margin - (m.exit != nil ? slotSize.height : 0)
    }

    /// Compact scale factor for narrow pages (1 on wide pages).
    private static func compactScale(width W: CGFloat, margin mg: CGFloat) -> CGFloat {
        W >= 500 ? 1 : max(0.8, min(1.4, (W - 2 * mg) / 342))
    }

    /// Page layout: the route-free content (`placeContent`), then the page-only rules (fit or grow, connector slot, route).
    private static func build(_ m: StopPageModel, metrics: PageMetrics, bandScale s: CGFloat, entryY: CGFloat?) -> StopLayout {
        let W = metrics.size.width, H0 = metrics.size.height, mg = metrics.margin
        let c = compactScale(width: W, margin: mg)
        let hasExit = m.exit != nil
        var L = placeContent(m, width: W, margin: mg, top: mg, bandScale: s)
        let wide = L.wide
        let slot = wide ? CGSize(width: 280, height: 100) : CGSize(width: 190 * c, height: 64)
        L.slotSize = hasExit ? slot : .zero

        if wide {
            // Fit: shrink the card to the room that is left rather than run into the connector slot.
            if L.photoCount >= 1 { L.fitCard(maxBottom: H0 - mg - (hasExit ? slot.height : 0)) }
            L.pageSize = CGSize(width: W, height: H0)
        } else {
            // The page grows with its content; the interactive view scrolls.
            let bottomPad = (L.seal != nil ? 44.0 : 0.0)
            var pageH = max(H0, L.contentBottom + bottomPad + (hasExit ? slot.height : 0) + mg)
            if hasExit { pageH = max(pageH, L.contentBottom + bottomPad + slot.height + mg) }
            L.pageSize = CGSize(width: W, height: pageH)
        }
        L.edit = CGRect(x: W - mg - 36, y: max(mg - 4, 4), width: 36, height: 36)
        L.anchor = pinAnchor(ticket: L.ticket, stopID: m.stopID)

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
        // Entry point: pinned to the previous page's absolute exit y. The page grows if that y lies below its own content
        // (done after the exit point is fixed, so this page's exit never depends on its neighbour).
        var entryOverride: CGPoint?
        if let entry = m.entry, let entryY, entry.edge == .left || entry.edge == .right {
            let y = max(entryY, 0)
            entryOverride = CGPoint(x: entry.edge == .left ? 0 : L.pageSize.width, y: y)
            L.pageSize.height = max(L.pageSize.height, y + mg)
        }
        L.route = RoutePlan.make(stopID: m.stopID, size: L.pageSize, anchor: L.anchor, entry: m.entry, exit: m.exit,
                                 entryPointOverride: entryOverride, exitPointOverride: exitOverride, slotSize: slot)
        return L
    }

    /// Anchor: centre of the numbered pin on the ticket (5,5 from its top-left), rotated with the ticket.
    static func pinAnchor(ticket: CGRect, stopID: String) -> CGPoint {
        let tc = CGPoint(x: ticket.midX, y: ticket.midY)
        let pinRaw = CGPoint(x: ticket.minX + 5, y: ticket.minY + 5)
        return PageRouteGeometry.rotate(pinRaw, around: tc, degrees: ticketRotation(stopID: stopID))
    }

    /// Shrinks the note card so it ends at `maxBottom` (never below 120pt tall); sets `cardClipped` when it had to.
    mutating func fitCard(maxBottom limit: CGFloat) {
        guard card.maxY > limit else { return }
        let cardH = card.height
        let room = max(limit - card.minY, 120)
        if room < cardH { card.size.height = room; cardClipped = true }
        contentBottom = card.maxY
    }

    /// Route-free placement of one stop's content (ticket, cost chip, photos, highlight, rating, note card, seal,
    /// postmark) in a `width`-wide area whose content starts at `top`. `pageSize` is left at (width, contentBottom);
    /// the caller applies its own rules (page fit or growth, connector slot, anchor, route).
    // swiftlint:disable:next function_body_length
    static func placeContent(_ m: StopPageModel, width W: CGFloat, margin mg: CGFloat, top y0: CGFloat,
                             bandScale s: CGFloat) -> StopLayout {
        let wide = W >= 500
        let cw = W - 2 * mg
        let n = min(m.photos.count, 4)
        let c = compactScale(width: W, margin: mg)
        let gap: CGFloat = 12
        let inset: CGFloat = wide ? 18 : 16
        let ratingH: CGFloat = (m.review?.isEmpty ?? true) ? 64 : 84
        let hasRating = m.rating != nil

        var L = StopLayout(pageSize: CGSize(width: W, height: 0), wide: wide, photoCount: n, route: RoutePlan(anchor: .zero))
        L.cardInset = inset
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
        } else {
            L.ticket = CGRect(x: mg + 8, y: y0 + 8, width: ticketW, height: ticketH)
            L.cost = costRect(below: L.ticket)
            cursorY = (L.cost ?? L.ticket).maxY + gap
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
                    }
                }
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
            var rowBottom = cursorY
            if let h = L.highlight { rowBottom = max(rowBottom, h.maxY) }
            if ratingInRow { rowBottom = max(rowBottom, cursorY + ratingH) }
            if L.highlight != nil || ratingInRow { cursorY = rowBottom + gap }
            if n == 0 { cursorY = max(cursorY, L.ticket.maxY + 24) }
            L.card = CGRect(x: mg, y: cursorY, width: cw, height: cardH)
            L.contentBottom = L.card.maxY
            if m.hasSeal { L.seal = CGRect(x: mg + 24, y: L.card.maxY - 12, width: 56, height: 56) }
        }
        L.pageSize = CGSize(width: W, height: L.contentBottom)
        return L
    }
}

/// Route-free layout of ONE stop for the composers: the same placement as a stop page (`StopLayout.placeContent`),
/// in block coordinates (origin = block top-left, x spans the full slice width so the side margins are included).
/// The block reports its height and where the route attaches (`routeAnchor`, the ticket pin); it draws no route.
nonisolated struct StopBlockLayout {
    /// Element frames in block coordinates (`route`, `slotSize`, `edit` unused).
    var frames: StopLayout
    var size: CGSize
    var routeAnchor: CGPoint
    var photoBandScale: CGFloat { frames.bandScale }

    /// `maxHeight`: when set, the note card shrinks (as on a full A4 page) so the block ends by then.
    static func make(_ m: StopPageModel, width: CGFloat, margin: CGFloat, photoBandScale: CGFloat = 1,
                     maxHeight: CGFloat? = nil) -> StopBlockLayout {
        var L = StopLayout.placeContent(m, width: width, margin: margin, top: 0, bandScale: photoBandScale)
        if let maxHeight, L.photoCount >= 1 {
            let overhang = L.seal.map { max($0.maxY - L.card.maxY, 0) } ?? 0
            L.fitCard(maxBottom: maxHeight - overhang)
            if let seal = L.seal { L.seal = CGRect(x: seal.minX, y: L.card.maxY - 12, width: seal.width, height: seal.height) }
        }
        L.anchor = StopLayout.pinAnchor(ticket: L.ticket, stopID: m.stopID)
        L.route = RoutePlan(anchor: L.anchor)
        let frames: [CGRect?] = [L.hero, L.ticket, L.cost, L.highlight, L.rating, L.card, L.seal, L.postmark] + L.taped.map { $0 }
        let bottom = frames.compactMap { $0?.maxY }.max() ?? 0
        L.pageSize = CGSize(width: width, height: ceil(bottom))
        return StopBlockLayout(frames: L, size: L.pageSize, routeAnchor: L.anchor)
    }
}

extension StopLayout {
    /// Absolute y at which the route enters page `index`, taken from the previous stop page's final exit point
    /// (nil when either neighbour is not a stop page with a crossing).
    static func entryY(at index: Int, in pages: [StoryPage], metrics: PageMetrics) -> CGFloat? {
        guard index > 0, index < pages.count,
              case .stop(let cur) = pages[index], cur.entry != nil,
              case .stop(let prev) = pages[index - 1], prev.exit != nil else { return nil }
        return make(prev, metrics: metrics).route.exitPoint?.y
    }
}
