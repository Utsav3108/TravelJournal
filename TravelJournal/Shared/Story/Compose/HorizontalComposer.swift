import Foundation
import CoreGraphics

/// Lays a journey out left to right in ONE wide canvas and cuts it into `spec.sliceSize` cards (the Instagram carousel).
///
/// 1. Slide order: cover (title and hero inside `spec.gridCropRect`, so they survive the profile grid's 3:4 crop), route
///    map (omitted when `mapMode == .hidden`), one panel of 1 or 2 slides per stop (`StopPanelLayout`), closing.
/// 2. The layout is FIXED: nothing tightens or changes with the slide count. `slideCount(for:)` only reports it.
/// 3. ONE route polyline in canvas coordinates: it starts at stop 1's ticket pin, runs along a horizontal lane across the
///    top of the stop slides, dips into every following ticket pin, and ends at "The End" on the last stop panel. A leg's
///    badge sits on the lane at the left of the stop it leads to, with the printed label and the leg story under it
///    (slides can't be tapped, so everything is printed).
/// 4. The polyline is cut at every slide edge: slide N's `routeExit` (x = width) and slide N+1's `routeEntry` (x = 0) are
///    the same canvas point, at the same y.
///
/// Blocks never cross a slide edge; only the route (and the washi tape drawn with the photos) does.
nonisolated struct HorizontalComposer: Composer {
    func compose(_ snapshot: JourneySnapshot, spec: OutputSpec) -> ComposedDocument {
        let size = spec.sliceSize
        let W = size.width
        var slices: [ComposedSlice] = []
        func add(_ kind: ComposedSlice.Kind, _ blocks: [PlacedBlock]) {
            slices.append(ComposedSlice(index: slices.count, kind: kind, size: size, blocks: blocks, route: [],
                                        routeEntry: nil, routeExit: nil, connectors: []))
        }

        // Cover: the block frame is the margin box, which lies inside the grid crop (the page lays out inside its margins).
        let coverFrame = spec.gridCropRect.map { spec.contentRect.intersection($0) } ?? spec.contentRect
        add(.cover, [PlacedBlock(id: "cover", content: .cover, frame: coverFrame, routeAnchor: nil)])
        let full = CGRect(origin: .zero, size: size)
        if snapshot.mapMode != .hidden {
            add(.map, [PlacedBlock(id: "map", content: .routeMap, frame: full, routeAnchor: nil)])
        }

        let firstStopSlide = slices.count
        let panelSlices = stopSlices(snapshot, spec: spec, firstSlide: firstStopSlide)
        for var s in panelSlices {
            s.index = slices.count
            slices.append(s)
        }
        add(.closing, [PlacedBlock(id: "closing", content: .closing, frame: full, routeAnchor: nil)])
        return ComposedDocument(slices: slices)
    }

    /// Slides the journey needs under `spec` (the carousel limit is 20; the layout never changes to meet it).
    static func slideCount(for snapshot: JourneySnapshot, spec: OutputSpec = .carousel) -> Int {
        HorizontalComposer().compose(snapshot, spec: spec).slices.count
    }

    // MARK: Stop panels

    // swiftlint:disable:next function_body_length
    private func stopSlices(_ s: JourneySnapshot, spec: OutputSpec, firstSlide: Int) -> [ComposedSlice] {
        let n = s.stops.count
        guard n > 0 else { return [] }
        let metrics = StopPanelLayout.Metrics(spec: spec)
        let W = spec.sliceSize.width
        let seal = s.sealStopIndex
        let models = (0..<n).map { s.stopPageModel($0, sealIndex: seal) }
        let panels = (0..<n).map { i in
            StopPanelLayout.make(models[i], legIn: i > 0 ? s.storyLeg(i - 1) : nil, isLast: i == n - 1, metrics: metrics)
        }
        // Canvas x of each panel's first slide.
        var firstSlideOf: [Int] = []
        var next = firstSlide
        for p in panels { firstSlideOf.append(next); next += p.slideCount }
        let stopSlideCount = next - firstSlide

        // Route, in canvas coordinates.
        let laneY = metrics.laneY, half = metrics.dipHalfWidth
        let pins: [CGPoint] = (0..<n).map { i in
            CGPoint(x: CGFloat(firstSlideOf[i]) * W + panels[i].anchor.x, y: panels[i].anchor.y)
        }
        func swingOut(_ pin: CGPoint) -> [CGPoint] {       // pin -> lane, leaving to the right
            let end = CGPoint(x: pin.x + half, y: laneY)
            return CubicBezier(p0: pin, c1: CGPoint(x: pin.x + half / 2, y: pin.y), c2: CGPoint(x: end.x - half / 2, y: laneY),
                               p3: end).flattened(24)
        }
        func swingIn(_ pin: CGPoint) -> [CGPoint] {        // lane -> pin, arriving from the left
            let start = CGPoint(x: pin.x - half, y: laneY)
            return CubicBezier(p0: start, c1: CGPoint(x: start.x + half / 2, y: laneY), c2: CGPoint(x: pin.x - half / 2, y: pin.y),
                               p3: pin).flattened(24)
        }
        var runs: [(points: [CGPoint], leg: Int?)] = []
        for i in 0..<(n - 1) {
            runs.append((swingOut(pins[i]) + swingIn(pins[i + 1]), i))
        }
        let lastSlideX = CGFloat(firstSlideOf[n - 1] + panels[n - 1].slideCount - 1) * W
        let endPoint = CGPoint(x: lastSlideX + metrics.endPoint.x, y: laneY)
        runs.append((swingOut(pins[n - 1]) + [endPoint], nil))
        let all = runs.flatMap(\.points)

        var out: [ComposedSlice] = []
        for k in 0..<stopSlideCount {
            let slideIndex = firstSlide + k
            let x0 = CGFloat(slideIndex) * W, x1 = x0 + W
            func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - x0, y: p.y) }

            // Which panel / part this slide is.
            let panelIndex = (0..<n).last(where: { firstSlideOf[$0] <= slideIndex }) ?? 0
            let panel = panels[panelIndex]
            let partIndex = slideIndex - firstSlideOf[panelIndex]
            let part = panel.parts[partIndex]
            let stop = s.stops[panelIndex]

            var blocks: [PlacedBlock] = []
            blocks.append(PlacedBlock(id: "stop-" + stop.id.uuidString + (partIndex == 0 ? "" : "-\(partIndex + 1)"),
                                      content: .stop(stopIndex: panelIndex, photoBandScale: panel.bandScale),
                                      frame: part.frame, routeAnchor: partIndex == 0 ? panel.anchor : nil))
            if let marker = panel.endMarker, partIndex == panel.slideCount - 1 {
                blocks.append(PlacedBlock(id: "end", content: .endMarker, frame: marker,
                                          routeAnchor: CGPoint(x: metrics.endPoint.x, y: laneY)))
            }
            var segments: [RouteSegment] = []
            for r in runs {
                let clipped = Self.clip(r.points, x0: x0, x1: x1)
                if clipped.count > 1 { segments.append(RouteSegment(points: clipped.map(local), legIndex: r.leg)) }
            }
            let entry = k > 0 ? Self.crossing(all, atX: x0).map(local) : nil
            let exit = k < stopSlideCount - 1 ? Self.crossing(all, atX: x1).map(local) : nil
            var connectors: [LegConnectorPlacement] = []
            if partIndex == 0, panelIndex > 0, let c = panel.connector {
                connectors.append(LegConnectorPlacement(legIndex: panelIndex - 1, center: c.center,
                                                        labelFrame: c.labelFrame, storyFrame: c.storyFrame))
            }
            out.append(ComposedSlice(index: 0, kind: .stops, size: spec.sliceSize, blocks: blocks, route: segments,
                                     routeEntry: entry, routeExit: exit, connectors: connectors))
        }
        return out
    }

    // MARK: Dash phase

    /// Length of route drawn on all slides before each slice, so the dashed line carries its pattern across slide edges
    /// (feed `offsets[i] ` to the slice's stroke as the dash phase, modulo the dash period).
    static func routeOffsets(_ doc: ComposedDocument) -> [CGFloat] {
        var total: CGFloat = 0
        return doc.slices.map { slice in
            defer {
                total += slice.route.reduce(0) { $0 + PageRouteGeometry.polylineLength($1.points) }
            }
            return total
        }
    }

    // MARK: Geometry

    /// The part of an x-monotonic polyline inside `x0...x1`, with interpolated end points on the bounds.
    static func clip(_ pts: [CGPoint], x0: CGFloat, x1: CGFloat) -> [CGPoint] {
        var out: [CGPoint] = []
        func append(_ p: CGPoint) { if out.last != p { out.append(p) } }
        for k in 1..<max(pts.count, 1) where pts.count > 1 {
            let a = pts[k - 1], b = pts[k]
            if a.x == b.x {
                if a.x >= x0 && a.x <= x1 { append(a); append(b) }
                continue
            }
            let (lo, hi) = (min(a.x, b.x), max(a.x, b.x))
            guard hi >= x0, lo <= x1 else { continue }
            func at(_ x: CGFloat) -> CGPoint {
                let t = (x - a.x) / (b.x - a.x)
                return CGPoint(x: x, y: a.y + (b.y - a.y) * t)
            }
            append(a.x < x0 ? at(x0) : (a.x > x1 ? at(x1) : a))
            append(b.x > x1 ? at(x1) : (b.x < x0 ? at(x0) : b))
        }
        return out
    }

    /// Where the polyline first crosses the vertical line `x` (nil when it never does).
    static func crossing(_ pts: [CGPoint], atX x: CGFloat) -> CGPoint? {
        for k in 1..<max(pts.count, 1) where pts.count > 1 {
            let a = pts[k - 1], b = pts[k]
            guard a.x != b.x, min(a.x, b.x) <= x, max(a.x, b.x) >= x else { continue }
            let t = (x - a.x) / (b.x - a.x)
            return CGPoint(x: x, y: a.y + (b.y - a.y) * t)
        }
        return nil
    }
}
