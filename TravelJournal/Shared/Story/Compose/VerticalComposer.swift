import Foundation
import CoreGraphics

/// Lays a journey out top to bottom in ONE document coordinate space and cuts it into `spec.sliceSize` pages.
///
/// 1. Measure each stop block (`StopBlockLayout`) at the slice width.
/// 2. Pack blocks and leg bands (connector badge + label + leg story) onto pages; a block or band never splits.
///    Page fill: before leaving a page more than a third empty, tighten the leg band, then shrink the next block's
///    photo band to 0.85.
/// 3. Build one route polyline: stop 1's ticket pin, down a margin lane past each block, through the leg band, into the
///    next ticket pin, and finally to the end marker.
/// 4. Cut the polyline at each page boundary; page N's exit and page N+1's entry are the same cut point.
///
/// Slice order: cover, route map (omitted when `mapMode == .hidden`), stop pages, closing.
nonisolated struct VerticalComposer: Composer {
    /// Spacing and sizes, in points.
    nonisolated struct Metrics: Hashable, Sendable {
        var laneInset: CGFloat = 30          // route lane x from the page edge (inside the margin)
        var badgeSide: CGFloat = 36
        var bandPad: CGFloat = 10            // above the connector row
        var crossRoom: CGFloat = 34          // under the row, where the route swings into the next pin
        var labelHeight: CGFloat = 18
        var labelWidth: CGFloat = 300
        var textGap: CGFloat = 10            // badge edge -> label/story
        var storyWidth: CGFloat = 250
        var storyMaxLines = 4
        var storyLineHeight: CGFloat = 23
        var storyInset: CGFloat = 10
        // Tight band (page fill)
        var tightPad: CGFloat = 4
        var tightCrossRoom: CGFloat = 24
        var tightStoryMaxLines = 2
        var shrunkPhotoBand: CGFloat = 0.85
        // End marker ("The End" stamp beside a flag where the route stops)
        var endMarkerSize = CGSize(width: 170, height: 64)
        var endMarkerGap: CGFloat = 30       // route run between the last block and the marker
        /// Pages may be at most this fraction empty (except the last stop page).
        var maxEmptyFraction: CGFloat = 1.0 / 3.0
    }

    var metrics = Metrics()

    init(metrics: Metrics = Metrics()) { self.metrics = metrics }

    func compose(_ snapshot: JourneySnapshot, spec: OutputSpec) -> ComposedDocument {
        var slices: [ComposedSlice] = []
        let size = spec.sliceSize
        let full = CGRect(origin: .zero, size: size)
        func add(_ kind: ComposedSlice.Kind, _ blocks: [PlacedBlock]) {
            slices.append(ComposedSlice(index: slices.count, kind: kind, size: size, blocks: blocks, route: [],
                                        routeEntry: nil, routeExit: nil, connectors: []))
        }
        add(.cover, [PlacedBlock(id: "cover", content: .cover, frame: full, routeAnchor: nil)])
        if snapshot.mapMode != .hidden {
            add(.map, [PlacedBlock(id: "map", content: .routeMap, frame: full, routeAnchor: nil)])
        }
        for var page in stopPages(snapshot, spec: spec) {
            page.index = slices.count
            slices.append(page)
        }
        add(.closing, [PlacedBlock(id: "closing", content: .closing, frame: full, routeAnchor: nil)])
        return ComposedDocument(slices: slices)
    }

    // MARK: Bands

    /// A leg band's geometry relative to its top: connector row, then room for the route to swing into the next pin.
    struct Band: Hashable {
        var height: CGFloat
        var rowTop: CGFloat
        var rowHeight: CGFloat
        var storyHeight: CGFloat          // 0 = no leg story
        var tight: Bool
        var badgeSide: CGFloat
        var badgeCenterY: CGFloat { rowTop + badgeSide / 2 }
        var rowBottom: CGFloat { rowTop + rowHeight }
    }

    func band(for leg: JourneySnapshot.LegSnapshot, tight: Bool) -> Band {
        let m = metrics
        var storyH: CGFloat = 0
        if let story = leg.story, !story.isEmpty {
            let lines = tight ? m.tightStoryMaxLines : m.storyMaxLines
            let textH = PageText.height(story, fontName: PageFont.caveat, size: 18, lineSpacing: 0,
                                        width: m.storyWidth - 2 * m.storyInset - 4)
            storyH = ceil(min(textH, CGFloat(lines) * m.storyLineHeight)) + 2 * m.storyInset
        }
        let labelBlock = m.badgeSide / 2 + m.labelHeight / 2 + 6     // label centred on the badge, story under it
        let rowH = storyH > 0 ? max(m.badgeSide, labelBlock + storyH) : m.badgeSide
        let pad = tight ? m.tightPad : m.bandPad
        let cross = tight ? m.tightCrossRoom : m.crossRoom
        return Band(height: pad + rowH + cross, rowTop: pad, rowHeight: rowH, storyHeight: storyH, tight: tight,
                    badgeSide: m.badgeSide)
    }

    // MARK: Packing

    private struct Placed {
        var page: Int
        var y: CGFloat                    // document y of the top
        var height: CGFloat
    }

    // swiftlint:disable:next function_body_length
    private func stopPages(_ s: JourneySnapshot, spec: OutputSpec) -> [ComposedSlice] {
        let n = s.stops.count
        guard n > 0 else { return [] }
        let m = metrics
        let W = spec.sliceSize.width, H = spec.sliceSize.height
        let content = spec.contentRect
        let seal = s.sealStopIndex
        let models = (0..<n).map { s.stopPageModel($0, sealIndex: seal) }

        var measured: [String: StopBlockLayout] = [:]
        func block(_ i: Int, _ scale: CGFloat) -> StopBlockLayout {
            let key = "\(i)@\(scale)"
            if let hit = measured[key] { return hit }
            let b = StopBlockLayout.make(models[i], width: W, margin: spec.margins.left, photoBandScale: scale,
                                         maxHeight: content.height)
            measured[key] = b
            return b
        }

        func top(_ page: Int) -> CGFloat { CGFloat(page) * H + content.minY }
        func bottom(_ page: Int) -> CGFloat { CGFloat(page) * H + content.maxY }
        let maxEmpty = content.height * m.maxEmptyFraction

        var page = 0
        var cursor = top(0)
        var blocks: [(placed: Placed, layout: StopBlockLayout)] = []
        var bands: [(placed: Placed, band: Band)] = []

        /// Places `h` at the cursor, or at the top of the next page when it does not fit.
        func place(_ h: CGFloat) -> Placed {
            if cursor + h > bottom(page) + 0.5, cursor > top(page) + 0.5 {
                page += 1
                cursor = top(page)
            }
            let p = Placed(page: page, y: cursor, height: h)
            cursor += h
            return p
        }

        // First block: shrink the photo band only if it cannot fit a page at all.
        var first = block(0, 1)
        if first.size.height > content.height { first = block(0, m.shrunkPhotoBand) }
        blocks.append((place(first.size.height), first))

        for i in 1..<n {
            let leg = s.legs[i - 1]
            let room = bottom(page) - cursor
            // Options, best first: normal band + full block, tight band + full block, tight band + shrunk block.
            let options: [(Band, StopBlockLayout)] = [
                (band(for: leg, tight: false), block(i, 1)),
                (band(for: leg, tight: true), block(i, 1)),
                (band(for: leg, tight: true), block(i, m.shrunkPhotoBand)),
            ]
            var chosen = options[0]
            if room - (chosen.0.height + chosen.1.size.height) < -0.5 {
                // Doesn't fit: only work harder when moving on would leave this page more than a third empty.
                let emptyIfMoved = chosen.0.height <= room ? room - chosen.0.height : room
                if emptyIfMoved > maxEmpty {
                    if let fit = options.dropFirst().first(where: { room - ($0.0.height + $0.1.size.height) >= -0.5 }) {
                        chosen = fit
                    }
                }
            }
            var b = chosen.1
            if b.size.height > content.height { b = block(i, m.shrunkPhotoBand) }
            let bandH = chosen.0.height
            if room - (bandH + b.size.height) < -0.5, bandH <= room + 0.5, cursor > top(page) + 0.5 {
                // The block starts the next page. The leg band sits in the middle of the room left on this one, so the
                // connector and its story fill the gap the route crosses instead of leaving a blank foot.
                bands.append((Placed(page: page, y: cursor + (room - bandH) / 2, height: bandH), chosen.0))
                page += 1
                cursor = top(page)
            } else {
                bands.append((place(bandH), chosen.0))
            }
            blocks.append((place(b.size.height), b))
        }

        // End marker: a short run of route, then the stamp.
        let endH = m.endMarkerGap + m.endMarkerSize.height
        let endPlaced = place(endH)
        let pageCount = page + 1

        // Lanes: the route runs down the margin on the side of each ticket pin.
        func lane(_ anchorX: CGFloat) -> CGFloat { anchorX < W / 2 ? m.laneInset : W - m.laneInset }
        let anchors: [CGPoint] = blocks.map { CGPoint(x: $0.layout.routeAnchor.x, y: $0.placed.y + $0.layout.routeAnchor.y) }

        // Route runs (document coordinates) and connectors.
        var runs: [(points: [CGPoint], leg: Int?)] = []
        var connectors: [(page: Int, placement: LegConnectorPlacement)] = []
        for i in 0..<(n - 1) {
            let a = anchors[i], next = anchors[i + 1]
            let x = lane(a.x)
            let bandPlaced = bands[i].placed, bd = bands[i].band
            let badge = CGPoint(x: x, y: bandPlaced.y + bd.badgeCenterY)
            var curveTop = max(bandPlaced.y + bd.rowBottom, blocks[i + 1].placed.y - (bd.height - bd.rowBottom))
            if blocks[i + 1].placed.page != bandPlaced.page { curveTop = max(curveTop, top(blocks[i + 1].placed.page) - content.minY + 2) }
            var pts = [a, CGPoint(x: x, y: a.y), badge, CGPoint(x: x, y: curveTop)]
            pts += swing(from: CGPoint(x: x, y: curveTop), to: next).dropFirst()
            runs.append((pts, i))
            connectors.append((bandPlaced.page, connector(leg: i, legSnap: s.legs[i], band: bd, badge: badge,
                                                          lane: x, W: W, pageTop: CGFloat(bandPlaced.page) * H)))
        }
        let last = anchors[n - 1]
        let endX = lane(last.x)
        let markerTop = endPlaced.y + m.endMarkerGap
        let endPoint = CGPoint(x: endX, y: markerTop + m.endMarkerSize.height / 2)
        runs.append(([last, CGPoint(x: endX, y: last.y), endPoint], nil))
        let markerX = endX < W / 2 ? endX - 6 : endX + 6 - m.endMarkerSize.width
        let markerFrame = CGRect(x: markerX, y: markerTop, width: m.endMarkerSize.width, height: m.endMarkerSize.height)

        // Cut into pages.
        let all = runs.flatMap(\.points)
        var out: [ComposedSlice] = []
        for p in 0..<pageCount {
            let y0 = CGFloat(p) * H, y1 = y0 + H
            func local(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x, y: pt.y - y0) }
            var placedBlocks: [PlacedBlock] = []
            for (i, b) in blocks.enumerated() where b.placed.page == p {
                placedBlocks.append(PlacedBlock(
                    id: "stop-" + s.stops[i].id.uuidString,
                    content: .stop(stopIndex: i, photoBandScale: b.layout.photoBandScale),
                    frame: CGRect(x: 0, y: b.placed.y - y0, width: W, height: b.layout.size.height),
                    routeAnchor: CGPoint(x: anchors[i].x, y: anchors[i].y - y0)))
            }
            if endPlaced.page == p {
                placedBlocks.append(PlacedBlock(id: "end", content: .endMarker, frame: markerFrame.offsetBy(dx: 0, dy: -y0),
                                                routeAnchor: local(endPoint)))
            }
            var segments: [RouteSegment] = []
            for r in runs {
                let clipped = Self.clip(r.points, y0: y0, y1: y1)
                if clipped.count > 1 { segments.append(RouteSegment(points: clipped.map(local), legIndex: r.leg)) }
            }
            let entry = p > 0 ? Self.crossing(all, atY: y0).map(local) : nil
            let exit = p < pageCount - 1 ? Self.crossing(all, atY: y1).map(local) : nil
            out.append(ComposedSlice(index: 0, kind: .stops, size: spec.sliceSize, blocks: placedBlocks, route: segments,
                                     routeEntry: entry, routeExit: exit,
                                     connectors: connectors.filter { $0.page == p }.map(\.placement)))
        }
        return out
    }

    // MARK: Geometry

    /// Smooth swing from the lane into a ticket pin, arriving from straight above.
    private func swing(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        let dy = max(b.y - a.y, 1)
        let curve = CubicBezier(p0: a, c1: CGPoint(x: a.x, y: a.y + dy * 0.55),
                                c2: CGPoint(x: b.x, y: b.y - dy * 0.55), p3: b)
        return curve.flattened(24)
    }

    private func connector(leg i: Int, legSnap: JourneySnapshot.LegSnapshot, band: Band, badge: CGPoint, lane: CGFloat,
                           W: CGFloat, pageTop: CGFloat) -> LegConnectorPlacement {
        let m = metrics
        let center = CGPoint(x: badge.x, y: badge.y - pageTop)
        let leftLane = lane < W / 2
        let textX = leftLane ? center.x + m.badgeSide / 2 + m.textGap : center.x - m.badgeSide / 2 - m.textGap
        let hasLabel = legSnap.mode != nil || legSnap.minutes != nil || legSnap.km != nil
        let labelW = min(m.labelWidth, leftLane ? W - textX - 12 : textX - 12)
        let labelFrame = hasLabel
            ? CGRect(x: leftLane ? textX : textX - labelW, y: center.y - m.labelHeight / 2, width: labelW, height: m.labelHeight)
            : nil
        var storyFrame: CGRect?
        if band.storyHeight > 0 {
            let y = center.y + m.labelHeight / 2 + 6
            storyFrame = CGRect(x: leftLane ? textX : textX - m.storyWidth, y: y, width: m.storyWidth, height: band.storyHeight)
        }
        return LegConnectorPlacement(legIndex: i, center: center, labelFrame: labelFrame, storyFrame: storyFrame)
    }

    /// The part of a (y-monotonic) polyline inside `y0...y1`, with interpolated end points on the bounds.
    static func clip(_ pts: [CGPoint], y0: CGFloat, y1: CGFloat) -> [CGPoint] {
        var out: [CGPoint] = []
        func append(_ p: CGPoint) { if out.last != p { out.append(p) } }
        for k in 1..<max(pts.count, 1) where pts.count > 1 {
            let a = pts[k - 1], b = pts[k]
            if a.y == b.y {
                if a.y >= y0 && a.y <= y1 { append(a); append(b) }
                continue
            }
            let (lo, hi) = (min(a.y, b.y), max(a.y, b.y))
            guard hi >= y0, lo <= y1 else { continue }
            func at(_ y: CGFloat) -> CGPoint {
                let t = (y - a.y) / (b.y - a.y)
                return CGPoint(x: a.x + (b.x - a.x) * t, y: y)
            }
            append(a.y < y0 ? at(y0) : (a.y > y1 ? at(y1) : a))
            append(b.y > y1 ? at(y1) : (b.y < y0 ? at(y0) : b))
        }
        return out
    }

    /// Where the polyline first crosses the horizontal line `y` (nil when it never does).
    static func crossing(_ pts: [CGPoint], atY y: CGFloat) -> CGPoint? {
        for k in 1..<max(pts.count, 1) where pts.count > 1 {
            let a = pts[k - 1], b = pts[k]
            guard a.y != b.y, min(a.y, b.y) <= y, max(a.y, b.y) >= y else { continue }
            let t = (y - a.y) / (b.y - a.y)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: y)
        }
        return nil
    }
}
