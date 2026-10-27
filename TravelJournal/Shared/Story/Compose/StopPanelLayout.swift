import Foundation
import CoreGraphics

/// Layout of ONE stop on the carousel: a panel of one or two slide widths. Every element sits inside one slide
/// (frames are slide-local, origin top-left); only the route and washi tape may cross slide edges, and the composer owns
/// the route.
///
/// Slide 1 of a panel (the "ticket slide") holds the hero polaroid on the left and, in the right-hand column, the place
/// ticket (its pin is where the route attaches), cost chip, highlight, rating and the taped photos. The connector for the
/// leg that leads INTO the stop (badge on the route lane, printed label, leg story) sits top-left on the same slide.
/// When the note card and seal don't fit under the photos, they go on slide 2.
///
/// Fixed rules, never driven by how many slides the whole journey needs: try the layout at full size, then with the photo
/// band at 0.85 (the same fallback as `StopLayout.make`), then split onto two slides.
nonisolated struct StopPanelLayout {
    /// Sizes and anchor positions, in points. `init(spec:)` derives them from the output spec.
    nonisolated struct Metrics: Hashable, Sendable {
        var slide: CGSize
        var margin: CGFloat
        /// y of the route lane (inside the top margin, above every block).
        var laneY: CGFloat = 36
        /// Top of the content area under the lane band.
        var contentTop: CGFloat = 76
        /// Route swing into / out of a ticket pin: horizontal distance from the pin to where the route rejoins the lane.
        var dipHalfWidth: CGFloat = 56
        var connectorTextWidth: CGFloat = 236
        var connectorGap: CGFloat = 12
        var storyMaxLines = 4
        var storyLineHeight: CGFloat = 23
        var endMarkerSize = CGSize(width: 150, height: 56)

        init(spec: OutputSpec) {
            slide = spec.sliceSize
            margin = spec.margins.left
        }

        var contentWidth: CGFloat { slide.width - 2 * margin }
        /// Lowest y content may reach.
        var bottom: CGFloat { slide.height - margin }
        /// Centre of the connector badge on the lane.
        var badgeCenter: CGPoint { CGPoint(x: margin + 26, y: laneY) }
        /// "The End" stamp, top-right of the last slide of the last panel; the flag's foot (the route's end) sits 6 pt in.
        var endMarkerFrame: CGRect {
            CGRect(x: slide.width - margin - endMarkerSize.width - 8, y: laneY - endMarkerSize.height / 2,
                   width: endMarkerSize.width, height: endMarkerSize.height)
        }
        var endPoint: CGPoint { CGPoint(x: endMarkerFrame.minX + RouteEndMarkerGeometry.flagInset, y: laneY) }
    }

    /// Where the route ends inside `RouteEndMarker` (kept here so layout stays nonisolated).
    nonisolated enum RouteEndMarkerGeometry { static let flagInset: CGFloat = 6 }

    /// The leg connector in front of a stop: badge on the lane, label and leg story under it.
    nonisolated struct Connector: Hashable, Sendable {
        var center: CGPoint
        var labelFrame: CGRect?
        var storyFrame: CGRect?
        /// Lowest y the connector reaches.
        var bottom: CGFloat
    }

    /// One slide of the panel: the elements on it (a `StopLayout` used as a frame carrier; empty rects are not drawn)
    /// and the union of their frames.
    nonisolated struct Part {
        var layout: StopLayout
        var frame: CGRect
    }

    var parts: [Part]
    /// Ticket pin on part 0, slide-local.
    var anchor: CGPoint
    /// Leg-in connector on part 0; nil for the first stop.
    var connector: Connector?
    /// "The End" stamp on the last part, when this is the last stop.
    var endMarker: CGRect?
    var bandScale: CGFloat

    var slideCount: Int { parts.count }

    // MARK: Make

    /// `legIn`: the leg arriving at this stop (nil for the first). `isLast`: the route ends here.
    static func make(_ m: StopPageModel, legIn: StoryLeg?, isLast: Bool,
                     metrics: Metrics = Metrics(spec: .carousel)) -> StopPanelLayout {
        let conn = legIn.map { connector($0, metrics) }
        // The hero (and what hangs under it) steps down to clear the connector's text; the ticket column stays high so
        // the route's swing into the pin stays short.
        let dy = conn.map { max(0, $0.bottom + metrics.connectorGap - (metrics.contentTop + 4)) } ?? 0

        var chosen: [Part]?
        var scale: CGFloat = 1
        for s in [1, 0.85] as [CGFloat] {
            let whole = wholeLayout(m, scale: s, dy: dy, metrics: metrics)
            if fits(whole, metrics) { chosen = [Part(layout: whole, frame: union(whole))]; scale = s; break }
        }
        if chosen == nil {
            // Two slides: photos, ticket and tags first; the note card (and seal) on the next.
            var a = wholeLayout(m, scale: 1, dy: dy, metrics: metrics)
            let cardH = a.card.height
            let inset = a.cardInset
            let hasSeal = a.seal != nil
            a.card = .zero
            a.seal = nil
            var b = StopLayout(pageSize: metrics.slide, wide: true, photoCount: a.photoCount, hero: nil,
                               route: RoutePlan(anchor: .zero))
            b.cardInset = inset
            var card = CGRect(x: metrics.margin, y: metrics.contentTop, width: metrics.contentWidth, height: cardH)
            let limit = metrics.bottom - (hasSeal ? 44 : 0)
            if card.maxY > limit {
                card.size.height = limit - card.minY
                b.cardClipped = true
            }
            b.card = card
            if hasSeal { b.seal = CGRect(x: metrics.margin + 24, y: card.maxY - 12, width: 56, height: 56) }
            chosen = [Part(layout: a, frame: union(a)), Part(layout: b, frame: union(b))]
        }
        var parts = chosen ?? []
        for i in parts.indices { parts[i].layout.pageSize = metrics.slide }
        parts[0].layout.anchor = StopLayout.pinAnchor(ticket: parts[0].layout.ticket, stopID: m.stopID)
        return StopPanelLayout(parts: parts, anchor: parts[0].layout.anchor, connector: conn,
                               endMarker: isLast ? metrics.endMarkerFrame : nil, bandScale: scale)
    }

    // MARK: Connector

    static func connector(_ leg: StoryLeg, _ metrics: Metrics) -> Connector {
        let hasLabel = leg.modeRaw != nil || leg.minutes != nil || leg.km != nil
        let story = (leg.story?.isEmpty ?? true) ? nil : leg.story
        let center = metrics.badgeCenter
        let x = metrics.margin + 8
        var bottom = center.y + 18
        var labelFrame: CGRect?
        if hasLabel {
            labelFrame = CGRect(x: x, y: center.y + 24, width: metrics.connectorTextWidth, height: 18)
            bottom = labelFrame!.maxY
        }
        var storyFrame: CGRect?
        if let story {
            let w = metrics.connectorTextWidth
            let textH = PageText.height(story, fontName: PageFont.caveat, size: 18, lineSpacing: 0, width: w - 24)
            let h = ceil(min(textH, CGFloat(metrics.storyMaxLines) * metrics.storyLineHeight)) + 20
            storyFrame = CGRect(x: x, y: (labelFrame?.maxY ?? center.y + 18) + 6, width: w, height: h)
            bottom = storyFrame!.maxY
        }
        return Connector(center: center, labelFrame: labelFrame, storyFrame: storyFrame, bottom: bottom)
    }

    // MARK: Single-slide layout

    /// Everything of the stop on one slide, with the hero band stepped down by `dy`.
    private static func wholeLayout(_ m: StopPageModel, scale s: CGFloat, dy: CGFloat, metrics: Metrics) -> StopLayout {
        let n = min(m.photos.count, 4)
        if n == 0 { return noPhotoLayout(m, dy: dy, metrics: metrics) }
        var L = StopLayout.placeContent(m, width: metrics.slide.width, margin: metrics.margin, top: metrics.contentTop,
                                        bandScale: s)
        guard dy > 0 else { return L }
        func down(_ r: inout CGRect) { r.origin.y += dy }
        if var h = L.hero { down(&h); L.hero = h }
        if n >= 2, n <= 3, var r = L.rating { down(&r); L.rating = r }      // under the hero; otherwise in the ticket column
        if n == 4 { for i in L.taped.indices { down(&L.taped[i]) } }        // the row under the band
        down(&L.card)
        if var seal = L.seal { down(&seal); L.seal = seal }
        L.contentBottom += dy
        return L
    }

    /// A stop without photos: the ticket column on the right as for every stop, the postmark on the left, the note under.
    private static func noPhotoLayout(_ m: StopPageModel, dy: CGFloat, metrics: Metrics) -> StopLayout {
        let W = metrics.slide.width, mg = metrics.margin, top = metrics.contentTop
        let colX = mg + 4 + 230 + 16
        let colW = W - mg - colX
        var L = StopLayout(pageSize: CGSize(width: W, height: 0), wide: true, photoCount: 0, hero: nil,
                           route: RoutePlan(anchor: .zero))
        L.cardInset = 18
        L.ticket = CGRect(x: colX + 8, y: top + 8, width: colW - 8, height: 72)
        var y = L.ticket.maxY + 8
        if let t = StopLayout.chipText(m) {
            let w = PageText.width(t, fontName: PageFont.elite, size: 11, tracking: 1.5) + 20
            L.cost = CGRect(x: L.ticket.minX, y: y, width: w, height: 22)
            y = L.cost!.maxY + 12
        } else {
            y += 4
        }
        if let h = m.highlight, !h.isEmpty {
            let text = PageText.width(h, fontName: PageFont.caveat, size: 18) + 20
            let oneLine = text <= colW
            L.highlight = CGRect(x: colX, y: y, width: oneLine ? text : colW, height: oneLine ? 32 : 56)
            y = L.highlight!.maxY + 12
        }
        if m.rating != nil {
            L.rating = CGRect(x: colX, y: y, width: 150, height: (m.review?.isEmpty ?? true) ? 64 : 84)
        }
        L.postmark = CGRect(x: mg + 4, y: top + 4 + dy, width: 96, height: 96)
        let columnBottom = max(L.rating?.maxY ?? 0, L.highlight?.maxY ?? 0, L.cost?.maxY ?? 0, L.ticket.maxY)
        let cw = metrics.contentWidth
        let storyH = PageText.height(m.story, fontName: PageFont.lora, size: StopLayout.storyFontSize,
                                     lineSpacing: StopLayout.storyLineSpacing, width: cw - 36)
        L.card = CGRect(x: mg, y: max(columnBottom + 18, L.postmark!.maxY + 18), width: cw,
                        height: max(storyH, 24) + 2 * 18 + 4)
        if m.hasSeal { L.seal = CGRect(x: mg + 24, y: L.card.maxY - 12, width: 56, height: 56) }
        L.contentBottom = L.card.maxY
        return L
    }

    // MARK: Helpers

    private static func rects(_ L: StopLayout) -> [CGRect] {
        [L.hero, L.ticket, L.cost, L.highlight, L.rating, L.card, L.seal, L.postmark].compactMap { $0 }.filter { !$0.isEmpty }
            + L.taped
    }

    static func union(_ L: StopLayout) -> CGRect {
        rects(L).reduce(CGRect.null) { $0.union($1) }
    }

    /// True when every element ends above the bottom margin (the seal may hang into it by up to 8 pt of the slide).
    private static func fits(_ L: StopLayout, _ metrics: Metrics) -> Bool {
        let body = rects(L).filter { $0 != L.seal }
        if body.contains(where: { $0.maxY > metrics.bottom + 0.5 }) { return false }
        if let seal = L.seal, seal.maxY > metrics.slide.height - 8 { return false }
        return true
    }
}
