import SwiftUI

/// Draws one `ComposedSlice` at exactly `slice.size`. Cover, map and closing slices reuse their page views; stop slices
/// draw the composer's route (one dashed run per segment), the stop blocks, the end marker and the leg connectors.
/// Photos come from the environment's `storyImageProvider`.
struct ComposedPageView: View {
    var slice: ComposedSlice
    var snapshot: JourneySnapshot
    var spec: OutputSpec
    /// Pre-fetched route map for print (`ImageRenderer` is synchronous); nil draws the illustrated fallback.
    var mapSnap: MapSnap?

    init(slice: ComposedSlice, snapshot: JourneySnapshot, spec: OutputSpec, mapSnap: MapSnap? = nil) {
        self.slice = slice
        self.snapshot = snapshot
        self.spec = spec
        self.mapSnap = mapSnap
        KraftFonts.register()
    }

    private var metrics: PageMetrics {
        PageMetrics(size: slice.size, margin: spec.margins.left, mode: spec.mode)
    }

    var body: some View {
        Group {
            switch slice.kind {
            case .cover where spec.isStoryFrames: StoryCoverFrame(model: snapshot.coverModel, spec: spec)
            case .cover: CoverPage(model: snapshot.coverModel, metrics: metrics)
            case .map: RouteOverviewPage(model: snapshot.overviewModel, metrics: metrics, snap: mapSnap, isLoading: false,
                                         mapMode: snapshot.mapMode)
            case .closing where spec.isStoryFrames: StoryClosingFrame(model: snapshot.closingModel, spec: spec)
            case .closing: ClosingPage(model: snapshot.closingModel, metrics: metrics)
            case .stops: stopsPage
            }
        }
        .frame(width: slice.size.width, height: slice.size.height)
        .clipped()
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
        .transaction { $0.animation = nil }
    }

    private var stopsPage: some View {
        let seal = snapshot.sealStopIndex
        return ZStack(alignment: .topLeading) {
            // 1. Route underlay.
            ForEach(Array(slice.route.enumerated()), id: \.offset) { _, seg in
                StoryPolyline(points: seg.points)
                    .stroke(KraftColor.route, style: StopRouteLayer.style)
            }
            .frame(width: slice.size.width, height: slice.size.height)
            .accessibilityHidden(true)

            // 2. Blocks.
            ForEach(slice.blocks) { block in
                switch block.content {
                case .stop(let i, let scale) where i < snapshot.stops.count:
                    // Story frames re-resolve the composer's fit (trimmed story, limited photos); A4 uses the scale it was given.
                    let fit = spec.isStoryFrames ? StoryStopFit.resolve(snapshot, spec: spec, index: i) : nil
                    let model = fit?.model ?? snapshot.stopPageModel(i, sealIndex: seal)
                    let layout = fit?.layout ?? StopBlockLayout.make(model, width: slice.size.width, margin: spec.margins.left,
                                                                      photoBandScale: scale,
                                                                      maxHeight: spec.contentRect.height)
                    StopContentLayer(model: model, layout: layout.frames, arrivalText: snapshot.arrivalText(i),
                                     interactive: spec.mode == .interactive)
                        .placed(CGRect(origin: block.frame.origin, size: layout.size), alignment: .topLeading)
                case .endMarker:
                    RouteEndMarker(size: block.frame.size,
                                   flagOnTrailing: (block.routeAnchor?.x ?? 0) > block.frame.midX,
                                   seed: "end/\(snapshot.id.uuidString)")
                        .placed(block.frame)
                default:
                    EmptyView()
                }
            }

            // 3. Leg connectors: badge on the route, printed label and leg story beside it.
            ForEach(slice.connectors, id: \.legIndex) { c in
                if c.legIndex < snapshot.legs.count { connector(c) }
            }
        }
        .frame(width: slice.size.width, height: slice.size.height, alignment: .topLeading)
        .background(PaperBackground())
    }

    @ViewBuilder private func connector(_ c: LegConnectorPlacement) -> some View {
        let leg = snapshot.storyLeg(c.legIndex)
        let leading = c.center.x < slice.size.width / 2      // text sits on the inner side of the lane
        let side = VerticalComposer.Metrics.resolved(for: spec).badgeSide
        if let r = c.storyFrame, let story = leg.story {
            LegStoryCard(story: story, legID: leg.id, size: r.size,
                         maxLines: max(1, Int((r.height - 20) / 23 + 0.5)))
                .placed(r, alignment: .topLeading)
        }
        if side == 36 {
            LegBadge(leg: leg)
                .placed(CGRect(x: c.center.x - 18, y: c.center.y - 18, width: 36, height: 36))
        } else {
            // Smaller badge for narrow frames (Story): the 36 pt badge scaled to the spec's size.
            LegBadge(leg: leg)
                .scaleEffect(side / 36)
                .frame(width: side, height: side)
                .placed(CGRect(x: c.center.x - side / 2, y: c.center.y - side / 2, width: side, height: side))
        }
        if let r = c.labelFrame {
            let label = LegBadge.label(leg)
            if !label.isEmpty {
                LegLabel(text: label)
                    .placed(r, alignment: leading ? .leading : .trailing)
            }
        }
    }
}

extension OutputSpec {
    /// Page metrics the existing page views lay out from (A4: `PageMetrics.a4`).
    var pageMetrics: PageMetrics { PageMetrics(size: sliceSize, margin: margins.left, mode: mode) }
}
