import Foundation
import CoreGraphics

nonisolated extension OutputSpec {
    /// Story-style frames: one stop per slice, kept clear of `safeInsets` (true for `.story` only).
    var isStoryFrames: Bool { safeInsets != .none }
}

/// How one stop is squeezed between the clear bands of a Story frame. Plans are tried in order; the first whose leg band +
/// stop block (+ end marker on the last stop) fits the room wins. The order follows the design:
///   (a) shorten the story to the first sentence (`StoryTrim`),
///   (b) shrink the photo band to 0.85,
///   (c) hero + one more photo,
/// then, because a 9:16 frame has far less room than an A4 page, a few last steps (tight leg band, smaller hero, clamped text).
nonisolated struct StoryStopPlan: Hashable, Sendable {
    var trimStory: Bool
    var heroScale: CGFloat            // 1, 0.85 (photo band scale), then smaller
    var maxPhotos: Int
    var tightBand: Bool
    var legStoryLines: Int
    var clampLines: Int?              // last resort: story cut to this many lines
    var dropCost = false              // last resort: no time-spent / cost chip

    static let ladder: [StoryStopPlan] = [
        StoryStopPlan(trimStory: false, heroScale: 1, maxPhotos: 4, tightBand: false, legStoryLines: 2),
        StoryStopPlan(trimStory: true, heroScale: 1, maxPhotos: 4, tightBand: false, legStoryLines: 2),
        StoryStopPlan(trimStory: true, heroScale: 0.85, maxPhotos: 4, tightBand: false, legStoryLines: 2),
        StoryStopPlan(trimStory: true, heroScale: 0.85, maxPhotos: 2, tightBand: false, legStoryLines: 2),
        StoryStopPlan(trimStory: true, heroScale: 0.85, maxPhotos: 2, tightBand: true, legStoryLines: 1),
        StoryStopPlan(trimStory: true, heroScale: 0.85, maxPhotos: 1, tightBand: true, legStoryLines: 1),
        StoryStopPlan(trimStory: true, heroScale: 0.85, maxPhotos: 1, tightBand: true, legStoryLines: 1, dropCost: true),
    ]
    /// Plans of last resort: the smallest hero with the story clamped to 4, 3, 2, 1 lines.
    static let clamped: [StoryStopPlan] = [4, 3, 2, 1].map {
        StoryStopPlan(trimStory: true, heroScale: 0.7, maxPhotos: 1, tightBand: true, legStoryLines: 1, clampLines: $0, dropCost: true)
    }
}

/// The resolved layout of one stop in a Story frame: the page model to draw (story trimmed, photos limited), the block's
/// frames, and the leg band that leads into it. The composer and `ComposedPageView` both call `resolve`, so what is
/// measured is what is drawn.
nonisolated struct StoryStopFit {
    var plan: StoryStopPlan
    var model: StopPageModel
    var layout: StopBlockLayout
    var band: VerticalComposer.Band?      // nil on the first stop
    var endReserve: CGFloat               // room kept under the last stop for the end marker
    var fits: Bool

    var totalHeight: CGFloat { (band?.height ?? 0) + layout.size.height + endReserve }

    /// Story text never goes below this size (3x render: 48 px).
    static var storyFontSize: CGFloat { StopLayout.storyFontSize }

    static func resolve(_ s: JourneySnapshot, spec: OutputSpec, index i: Int, composer: VerticalComposer = VerticalComposer())
        -> StoryStopFit {
        let m = composer.resolvedMetrics(for: spec)
        let base = s.stopPageModel(i, sealIndex: s.sealStopIndex)
        let isLast = i == s.stops.count - 1
        let reserve = isLast ? m.endMarkerGap + m.endMarkerSize.height : 0
        let room = spec.safeContentRect.height - 4          // 4 pt for rotated cards
        let cw = spec.sliceSize.width - 2 * spec.margins.left
        var best: StoryStopFit?
        for plan in StoryStopPlan.ladder + StoryStopPlan.clamped {
            let model = prepared(base, plan: plan, cardWidth: cw - 2 * cardInset)
            let layout = StoryBlockLayout.make(model, spec: spec, heroWidth: heroBase(spec) * plan.heroScale, dropCost: plan.dropCost)
            let band = i > 0 ? composer.band(for: s.legs[i - 1], tight: plan.tightBand, storyLines: plan.legStoryLines, metrics: m) : nil
            let fit = StoryStopFit(plan: plan, model: model, layout: layout, band: band, endReserve: reserve, fits: false)
            best = fit
            if fit.totalHeight <= room {
                var ok = fit
                ok.fits = true
                return ok
            }
        }
        return best!
    }

    static let cardInset: CGFloat = 14
    static func heroBase(_ spec: OutputSpec) -> CGFloat { ((spec.sliceSize.width - 2 * spec.margins.left) * 0.375).rounded() }

    private static func prepared(_ m: StopPageModel, plan: StoryStopPlan, cardWidth: CGFloat) -> StopPageModel {
        var out = m
        out.photos = Array(m.photos.prefix(plan.maxPhotos))
        if plan.trimStory { out.story = StoryTrim.trimmed(m.story) }
        if let lines = plan.clampLines {
            out.story = StoryTrim.clamp(out.story, fontName: PageFont.lora, size: StopLayout.storyFontSize,
                                        lineSpacing: StopLayout.storyLineSpacing, width: cardWidth, maxLines: lines)
        }
        return out
    }
}

/// Block layout for a Story frame: ticket on top, hero polaroid below it with a column beside it (extra photos, or the
/// highlight, rating and cost chip), then the story card. Frames are in block coordinates (x spans the whole frame).
nonisolated enum StoryBlockLayout {
    private enum Extra { case highlight, rating, cost }

    private static func subsets(of items: [Extra]) -> [[Extra]] {
        (0..<(1 << items.count)).map { mask in items.indices.filter { mask & (1 << $0) != 0 }.map { items[$0] } }
    }

    static func make(_ m: StopPageModel, spec: OutputSpec, heroWidth hw: CGFloat, dropCost: Bool = false) -> StopBlockLayout {
        let W = spec.sliceSize.width, mg = spec.margins.left, cw = W - 2 * mg
        let n = min(m.photos.count, 4)
        let inset = StoryStopFit.cardInset
        var L = StopLayout(pageSize: CGSize(width: W, height: 0), wide: false, photoCount: n, route: RoutePlan(anchor: .zero))
        L.cardInset = inset

        L.ticket = CGRect(x: mg + 8, y: 8, width: min(250, cw - 8), height: 64)
        if m.hasSeal { L.seal = CGRect(x: W - mg - 58, y: 12, width: 56, height: 56) }    // beside the ticket: costs no height

        let ratingH: CGFloat = (m.review?.isEmpty ?? true) ? 64 : 84
        func size(_ e: Extra, avail: CGFloat) -> CGSize? {
            switch e {
            case .highlight:
                guard let h = m.highlight, !h.isEmpty else { return nil }
                let text = PageText.width(h, fontName: PageFont.caveat, size: 18) + 20
                return text <= avail ? CGSize(width: text, height: 32) : CGSize(width: avail, height: 56)
            case .rating:
                return m.rating == nil ? nil : CGSize(width: 150, height: ratingH)
            case .cost:
                guard !dropCost, let t = StopLayout.chipText(m) else { return nil }
                return CGSize(width: min(PageText.width(t, fontName: PageFont.elite, size: 11, tracking: 1.5) + 20, avail), height: 22)
            }
        }

        let top = L.ticket.maxY + 8
        var hero: CGRect?
        var colX: CGFloat = 0, colW: CGFloat = 0
        if n >= 1 {
            let h = CGRect(x: mg + 4, y: top, width: hw, height: hw * 1.17)
            hero = h
            L.hero = h
            colX = h.maxX + 14
            colW = W - mg - colX
            if n >= 2 {
                // Taped photos fill the column; the highlight / rating / cost chip go to a row under the photo band.
                let k = min(n - 1, 2), gap: CGFloat = 8
                let outerH = (h.height - CGFloat(k - 1) * gap) / CGFloat(k)
                let outerW = min(colW - 8, (outerH - 8) / 0.74 + 8)
                L.taped = (0..<k).map { j in
                    CGRect(x: colX + (colW - outerW) / 2, y: top + CGFloat(j) * (outerH + gap), width: outerW, height: outerH)
                }
                L.tapedTapes = 1
            }
        }
        let bandBottom = hero?.maxY ?? L.ticket.maxY
        let extras = [Extra.highlight, .rating, .cost].filter { size($0, avail: cw) != nil }

        /// Puts `column` beside the hero (single-photo stops, when they fit) and the rest in a row under the band.
        func arrange(column: [Extra]) -> (frames: [Extra: CGRect], bottom: CGFloat)? {
            var frames: [Extra: CGRect] = [:]
            var y = top
            for e in column {
                guard let h = hero, let sz = size(e, avail: colW), y + sz.height <= h.maxY + 0.5 else { return nil }
                frames[e] = CGRect(x: colX, y: y, width: sz.width, height: sz.height)
                y += sz.height + 8
            }
            let rest = extras.filter { !column.contains($0) }
            var bottom = bandBottom
            if !rest.isEmpty {
                let y0 = bandBottom + 8
                let hasRating = rest.contains(.rating)
                let leftW = cw - 8 - (hasRating ? 162 : 0)
                var leftY = y0
                if rest.contains(.highlight), let sz = size(.highlight, avail: leftW) {
                    frames[.highlight] = CGRect(x: mg + 8, y: leftY, width: sz.width, height: sz.height)
                    leftY += sz.height + 6
                }
                if hasRating, let sz = size(.rating, avail: 150) {
                    frames[.rating] = CGRect(x: W - mg - 156, y: y0, width: sz.width, height: sz.height)
                }
                var rowBottom = max(leftY - 6, hasRating ? y0 + ratingH : y0)
                if rest.contains(.cost), let sz = size(.cost, avail: cw - 8) {
                    // Under the highlight when it fits beside the rating, else on its own line under both.
                    let beside = sz.width <= leftW
                    let cy = beside ? max(leftY, y0) : rowBottom + 6
                    frames[.cost] = CGRect(x: mg + 8, y: cy, width: sz.width, height: sz.height)
                    rowBottom = max(rowBottom, cy + sz.height)
                }
                bottom = rowBottom
            }
            return (frames, bottom)
        }
        // Try every split between the column and the row; keep the shortest (then the one with more beside the hero).
        var best: (frames: [Extra: CGRect], bottom: CGFloat, inColumn: Int)?
        let candidates: [[Extra]] = n == 1 ? subsets(of: extras) : [[]]
        for column in candidates {
            guard let a = arrange(column: column) else { continue }
            if best == nil || a.bottom < best!.bottom - 0.5 || (abs(a.bottom - best!.bottom) <= 0.5 && column.count > best!.inColumn) {
                best = (a.frames, a.bottom, column.count)
            }
        }
        let placed: (frames: [Extra: CGRect], bottom: CGFloat)
        if let best { placed = (best.frames, best.bottom) } else { placed = arrange(column: [])! }
        L.highlight = placed.frames[.highlight]
        L.rating = placed.frames[.rating]
        L.cost = placed.frames[.cost]
        let rowBottom = placed.bottom

        let textH = PageText.height(m.story, fontName: PageFont.lora, size: StopLayout.storyFontSize,
                                    lineSpacing: StopLayout.storyLineSpacing, width: cw - 2 * inset)
        L.card = CGRect(x: mg, y: rowBottom + 10, width: cw, height: max(textH, 24) + 2 * inset + 4)
        L.contentBottom = L.card.maxY
        L.anchor = StopLayout.pinAnchor(ticket: L.ticket, stopID: m.stopID)
        L.route = RoutePlan(anchor: L.anchor)
        let frames: [CGRect?] = [L.hero, L.ticket, L.cost, L.highlight, L.rating, L.card, L.seal] + L.taped.map { $0 }
        L.pageSize = CGSize(width: W, height: ceil(frames.compactMap { $0?.maxY }.max() ?? 0))
        return StopBlockLayout(frames: L, size: L.pageSize, routeAnchor: L.anchor)
    }
}
