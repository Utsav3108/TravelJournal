import SwiftUI

/// Draws one carousel slide (`ComposedSlice` from `HorizontalComposer`) at exactly `slice.size`. Cover, map and closing
/// slides reuse their page views; stop slides draw the route (one dashed run per segment, its dash pattern continuing across
/// slide edges), the stop's elements, the leg connector and the end marker.
/// Photos come from the environment's `storyImageProvider`.
struct CarouselSliceView: View {
    var slice: ComposedSlice
    var snapshot: JourneySnapshot
    var spec: OutputSpec = .carousel
    /// Pre-fetched route map for print (`ImageRenderer` is synchronous); nil draws the illustrated fallback.
    var mapSnap: MapSnap?
    /// Length of route drawn on earlier slides (`HorizontalComposer.routeOffsets`), so the dashes line up at the seam.
    var routeOffset: CGFloat = 0
    /// Print "Made with TravelJournal" on the closing slide (`ExportPrivacy.showBrandStamp`).
    var showsBrandStamp = false

    init(slice: ComposedSlice, snapshot: JourneySnapshot, spec: OutputSpec = .carousel, mapSnap: MapSnap? = nil,
         routeOffset: CGFloat = 0, showsBrandStamp: Bool = false) {
        self.slice = slice
        self.snapshot = snapshot
        self.spec = spec
        self.mapSnap = mapSnap
        self.routeOffset = routeOffset
        self.showsBrandStamp = showsBrandStamp
        KraftFonts.register()
    }

    private var metrics: PageMetrics { spec.pageMetrics }

    var body: some View {
        Group {
            switch slice.kind {
            case .cover: CoverPage(model: snapshot.coverModel, metrics: metrics)
            case .map: RouteOverviewPage(model: snapshot.overviewModel, metrics: metrics, snap: mapSnap, isLoading: false,
                                         mapMode: snapshot.mapMode)
            case .closing: ClosingPage(model: snapshot.closingModel, metrics: metrics)
                    .environment(\.exportBrandStamp, showsBrandStamp)
            case .stops: stopsSlide
            }
        }
        .frame(width: slice.size.width, height: slice.size.height)
        .clipped()
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
        .transaction { $0.animation = nil }
    }

    // MARK: Stop slide

    /// Same stroke as `StopRouteLayer.style`, with the dash phase carried over from the previous slide.
    private func style(phase: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: PageRouteGeometry.lineWidth, lineCap: .round, lineJoin: .round,
                    dash: [PageRouteGeometry.dash, PageRouteGeometry.gap],
                    dashPhase: phase.truncatingRemainder(dividingBy: PageRouteGeometry.period))
    }

    private var stopsSlide: some View {
        let seal = snapshot.sealStopIndex
        // Where each segment starts along the route: this slice's offset plus the segments before it.
        var starts: [CGFloat] = []
        var run = routeOffset
        for seg in slice.route {
            starts.append(run)
            run += PageRouteGeometry.polylineLength(seg.points)
        }
        return ZStack(alignment: .topLeading) {
            // 1. Route underlay.
            ForEach(Array(slice.route.enumerated()), id: \.offset) { i, seg in
                StoryPolyline(points: seg.points)
                    .stroke(KraftColor.route, style: style(phase: starts[i]))
            }
            .frame(width: slice.size.width, height: slice.size.height)
            .accessibilityHidden(true)

            // 2. Stop elements and the end marker.
            ForEach(slice.blocks) { block in
                switch block.content {
                case .stop(let i, _) where i < snapshot.stops.count:
                    stopPart(i, block: block, sealIndex: seal)
                case .endMarker:
                    RouteEndMarker(size: block.frame.size, flagOnTrailing: false, seed: "end/\(snapshot.id.uuidString)")
                        .placed(block.frame)
                default:
                    EmptyView()
                }
            }

            // 3. Leg connector: badge on the route lane, printed label and leg story under it.
            ForEach(slice.connectors, id: \.legIndex) { c in
                if c.legIndex < snapshot.legs.count { connector(c) }
            }
        }
        .frame(width: slice.size.width, height: slice.size.height, alignment: .topLeading)
        .background(PaperBackground())
    }

    @ViewBuilder private func stopPart(_ i: Int, block: PlacedBlock, sealIndex: Int?) -> some View {
        let model = snapshot.stopPageModel(i, sealIndex: sealIndex)
        let partIndex = block.id.hasSuffix("-2") ? 1 : 0
        let panel = StopPanelLayout.make(model, legIn: i > 0 ? snapshot.storyLeg(i - 1) : nil, isLast: i == snapshot.stops.count - 1,
                                         metrics: StopPanelLayout.Metrics(spec: spec))
        if partIndex < panel.parts.count {
            CarouselStopLayer(model: model, layout: panel.parts[partIndex].layout, arrivalText: snapshot.arrivalText(i))
        }
    }

    @ViewBuilder private func connector(_ c: LegConnectorPlacement) -> some View {
        let leg = snapshot.storyLeg(c.legIndex)
        if let r = c.storyFrame, let story = leg.story {
            LegStoryCard(story: story, legID: leg.id, size: r.size,
                         maxLines: max(1, Int((r.height - 20) / 23 + 0.5)))
                .placed(r, alignment: .topLeading)
        }
        LegBadge(leg: leg)
            .placed(CGRect(x: c.center.x - 18, y: c.center.y - 18, width: 36, height: 36))
        if let r = c.labelFrame {
            let label = LegBadge.label(leg)
            if !label.isEmpty { LegLabel(text: label).placed(r, alignment: .leading) }
        }
    }
}

/// The elements of one carousel stop slide (a part of `StopPanelLayout`): the same pieces as `StopContentLayer`, but each
/// is drawn only when the part has a frame for it (the note card and seal can sit on the panel's second slide).
struct CarouselStopLayer: View {
    var model: StopPageModel
    var layout: StopLayout
    var arrivalText: String?

    @Environment(\.storyImageProvider) private var provider
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let L = layout
        let loader = StoryPhotoLoader(provider: provider, interactive: false, displayScale: displayScale)
        let id = model.stopID
        let photos = Array(model.photos.prefix(4))
        ZStack(alignment: .topLeading) {
            if let hero = L.hero, let p = photos.first {
                Polaroid(photo: loader.image(p, label: model.name.isEmpty ? "Photo" : model.name, points: hero.width),
                         caption: model.name, width: hero.width, seed: "\(id)/hero")
                    .placed(hero)
            }
            ForEach(Array(L.taped.enumerated()), id: \.offset) { i, rect in
                let idx = i + 1
                if idx < photos.count {
                    let p = photos[idx]
                    let tapes = L.photoCount == 2 ? 2 : (L.photoCount == 3 && i == 0 ? 2 : 1)
                    TapedPhoto(photo: loader.image(p, points: rect.width),
                               size: CGSize(width: rect.width - 8, height: rect.height - 8),
                               tapes: tapes, seed: "\(id)/photo/\(p.id)")
                        .placed(rect)
                }
            }
            if !L.card.isEmpty { noteCard(L).placed(L.card, alignment: .topLeading) }
            if let r = L.highlight, let h = model.highlight {
                HighlightStrip(text: h, seed: "\(id)/highlight", showsArrow: false)
                    .placed(r, alignment: .leading)
            }
            if let r = L.cost, let t = StopLayout.chipText(model) {
                Text(t)
                    .stampLabel()
                    .foregroundStyle(KraftColor.ink)
                    .lineLimit(1)
                    .frame(width: r.width, height: r.height)
                    .background(KraftColor.paper)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .stroke(KraftColor.kraftDark, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .rotationEffect(.degrees(PageSeed.rotation(id: "\(id)/cost", limit: 2)))
                    .placed(r)
            }
            if !L.ticket.isEmpty {
                PlaceTicket(number: model.index + 1, name: model.name,
                            category: KraftCategory(rawValue: model.categoryRaw) ?? .other,
                            arrived: arrivalText, spentMinutes: nil,
                            width: L.ticket.width, height: L.ticket.height, seed: "\(id)/ticket")
                    .placed(L.ticket)
            }
            if let r = L.rating, let stars = model.rating {
                RatingStamp(rating: stars, review: model.review, seed: "\(id)/rating")
                    .placed(r)
            }
            if let r = L.postmark {
                StoryPostmark(top: "STOP \(model.index + 1)", bottom: "OF \(model.total)",
                              center: arrivalText ?? "", size: r.width, seed: "\(id)/postmark")
                    .placed(r)
            }
            if let r = L.seal {
                WaxSeal(glyph: String(model.name.first.map { String($0).uppercased() } ?? "T"), size: r.width, seed: "\(id)/seal")
                    .placed(r)
            }
        }
        .frame(width: L.pageSize.width, height: L.pageSize.height, alignment: .topLeading)
    }

    @ViewBuilder private func noteCard(_ L: StopLayout) -> some View {
        let variant = L.photoCount == 0 ? 2 : Int(model.seed % 3)
        NoteCard(variant: variant, seed: "\(model.stopID)/note", inset: L.cardInset) {
            if L.cardClipped {
                // Last resort: shrink the type rather than run off the slide.
                Text(model.story).storyBody().foregroundStyle(KraftColor.ink)
                    .minimumScaleFactor(0.75)
                    .frame(maxHeight: L.card.height - 2 * L.cardInset, alignment: .topLeading)
            } else {
                Text(model.story).storyBody().foregroundStyle(KraftColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: L.card.width, height: L.card.height, alignment: .topLeading)
    }
}
