import Foundation
import CoreGraphics

/// One stop per slice (Story frames). Each stop frame holds, top to bottom: the leg band leading into the stop (connector
/// badge, label and leg story), then the stop block (and, on the last stop, the end marker), all between the spec's
/// clear bands (`safeContentRect`). The route enters at y = 0 and leaves at y = height on the lane, so it joins the next
/// frame at the same x, and it runs through the bands because it is a background line, not something to read.
///
/// Instagram's own UI covers the top and bottom of a Story, so nothing the viewer must read goes there. Band sizes: Meta's
/// guidance is to keep roughly the top 14% (about 250 px of 1920) and the bottom 20% (about 340 px; some sources say up to
/// 380) free of text and logos; the spec's 14% / 20% (269 / 384 px) stay on the safe side of both.
/// https://www.firstpier.com/resources/instagram-ad-safe-zones
/// https://socialsizes.io/instagram-stories-size/
///
/// No map frame: the overview page is built for A4 (a fixed 400 pt map, stats strip and stop list) and cannot be read
/// between the bands at 9:16, and every stop frame already carries the route. So `mapMode` needs no handling here.
extension VerticalComposer {
    func composeFrames(_ s: JourneySnapshot, spec: OutputSpec) -> ComposedDocument {
        let m = resolvedMetrics(for: spec)
        let size = spec.sliceSize
        let W = size.width, H = size.height
        let safe = spec.safeContentRect
        var slices: [ComposedSlice] = []
        func add(_ kind: ComposedSlice.Kind, _ blocks: [PlacedBlock], route: [RouteSegment] = [], entry: CGPoint? = nil,
                 exit: CGPoint? = nil, connectors: [LegConnectorPlacement] = []) {
            slices.append(ComposedSlice(index: slices.count, kind: kind, size: size, blocks: blocks, route: route,
                                        routeEntry: entry, routeExit: exit, connectors: connectors))
        }
        add(.cover, [PlacedBlock(id: "cover", content: .cover, frame: safe, routeAnchor: nil)])

        let n = s.stops.count
        let fits = (0..<n).map { StoryStopFit.resolve(s, spec: spec, index: $0, composer: self) }
        func lane(_ anchorX: CGFloat) -> CGFloat { anchorX < W / 2 ? m.laneInset : W - m.laneInset }
        let laneXs = fits.map { lane($0.layout.routeAnchor.x) }

        for i in 0..<n {
            let f = fits[i]
            let top = safe.minY + max(0, safe.height - f.totalHeight) / 2
            let bandH = f.band?.height ?? 0
            let blockTop = top + bandH
            let pin = CGPoint(x: f.layout.routeAnchor.x, y: blockTop + f.layout.routeAnchor.y)
            let x = laneXs[i]
            var route: [RouteSegment] = []
            var connectors: [LegConnectorPlacement] = []
            var blocks: [PlacedBlock] = []

            if i > 0, let band = f.band {
                let xIn = laneXs[i - 1]
                let badge = CGPoint(x: xIn, y: top + band.badgeCenterY)
                let curveTop = max(top + band.rowBottom, blockTop - (band.height - band.rowBottom))
                var pts = [CGPoint(x: xIn, y: 0), badge, CGPoint(x: xIn, y: curveTop)]
                pts += swing(from: CGPoint(x: xIn, y: curveTop), to: pin).dropFirst()
                route.append(RouteSegment(points: pts, legIndex: i - 1))
                connectors.append(connector(leg: i - 1, legSnap: s.legs[i - 1], band: band, badge: badge, lane: xIn, W: W,
                                            pageTop: 0, metrics: m))
            }
            blocks.append(PlacedBlock(id: "stop-" + s.stops[i].id.uuidString,
                                      content: .stop(stopIndex: i, photoBandScale: f.plan.heroScale),
                                      frame: CGRect(x: 0, y: blockTop, width: W, height: f.layout.size.height),
                                      routeAnchor: pin))

            if i < n - 1 {
                route.append(RouteSegment(points: [pin, CGPoint(x: x, y: pin.y), CGPoint(x: x, y: H)], legIndex: i))
            } else {
                let markerTop = blockTop + f.layout.size.height + m.endMarkerGap
                let endPoint = CGPoint(x: x, y: markerTop + m.endMarkerSize.height / 2)
                route.append(RouteSegment(points: [pin, CGPoint(x: x, y: pin.y), endPoint], legIndex: nil))
                let markerX = x < W / 2 ? x - 6 : x + 6 - m.endMarkerSize.width
                blocks.append(PlacedBlock(id: "end", content: .endMarker,
                                          frame: CGRect(x: markerX, y: markerTop, width: m.endMarkerSize.width,
                                                        height: m.endMarkerSize.height),
                                          routeAnchor: endPoint))
            }
            add(.stops, blocks, route: route, entry: i > 0 ? CGPoint(x: laneXs[i - 1], y: 0) : nil,
                exit: i < n - 1 ? CGPoint(x: x, y: H) : nil, connectors: connectors)
        }
        add(.closing, [PlacedBlock(id: "closing", content: .closing, frame: safe, routeAnchor: nil)])
        return ComposedDocument(slices: slices)
    }
}
