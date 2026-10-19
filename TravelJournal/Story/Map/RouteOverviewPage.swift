import SwiftUI

/// Route overview page: header, torn-paper map card with vector route + numbered pins, stats strip,
/// and the list of stops (those without coordinates are marked "not on the map").
/// Pure view: all assets arrive via `snap` (nil -> illustrated fallback computed inline), so it renders
/// synchronously in ImageRenderer / PDF. Callbacks are ignored in print mode.
struct RouteOverviewPage: View {
    var model: OverviewModel
    var metrics: PageMetrics
    var snap: MapSnap?
    var isLoading: Bool = false
    var onPinTap: ((String) -> Void)?
    var onLegTap: ((StoryLeg) -> Void)?

    private var interactive: Bool { metrics.mode == .interactive }
    private var mapSize: CGSize { MapSnapshotService.mapSize(for: metrics) }
    private var resolved: MapSnap { snap ?? MapSnapshotService.fallback(for: model, size: mapSize) }

    var body: some View {
        ZStack(alignment: .top) {
            PaperBackground()
            VStack(alignment: .leading, spacing: 16) {
                header
                mapCard
                OverviewStatsStrip(stats: model.stats)
                stopList
                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.margin)
            .padding(.top, metrics.margin)
            .padding(.bottom, metrics.margin)
            .frame(width: metrics.size.width, height: metrics.mode == .print ? metrics.size.height : nil, alignment: .top)
        }
        .frame(width: metrics.size.width, height: metrics.mode == .print ? metrics.size.height : nil, alignment: .top)
        .clipped()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Day map").stampLabel().foregroundStyle(KraftColor.inkSoft)
            Text("The route")
                .font(KraftFont.title(40))
                .foregroundStyle(KraftColor.ink)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Map card

    private var mapCard: some View {
        let snap = resolved
        let size = mapSize
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(KraftColor.polaroidWhite)
                .shadow(color: KraftColor.shadow, radius: 4, y: 2)
            ZStack {
                Image(uiImage: snap.image).resizable().frame(width: size.width, height: size.height)
                routeOverlay(snap: snap, size: size)
                if isLoading {
                    ProgressView().tint(KraftColor.kraftDark)
                        .padding(10).background(KraftColor.paper.opacity(0.85), in: Capsule())
                }
                if snap.pins.isEmpty {
                    Text("No locations for this day").font(KraftFont.note(20)).foregroundStyle(KraftColor.inkSoft)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(KraftColor.paper.opacity(0.85))
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .padding(6)
        }
        .frame(width: size.width + 12, height: size.height + 12)
        .overlay(alignment: .topLeading) { WashiTape(variant: .kraft).rotationEffect(.degrees(-6)).offset(x: -14, y: -9) }
        .overlay(alignment: .topTrailing) { WashiTape(variant: .pinkGrid).rotationEffect(.degrees(5)).offset(x: 14, y: -9) }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func routeOverlay(snap: MapSnap, size: CGSize) -> some View {
        let sx = size.width / max(snap.size.width, 1), sy = size.height / max(snap.size.height, 1)
        let pts = snap.pins.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        let indices = snap.stopIndices.count == pts.count ? snap.stopIndices : Array(pts.indices)
        let segs = MapProjection.segments(located: indices, legCount: model.legs.count)
        ZStack {
            // Vector route line.
            Path { p in
                guard let f = pts.first else { return }
                p.move(to: f)
                for q in pts.dropFirst() { p.addLine(to: q) }
            }
            .stroke(KraftColor.route, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [7, 5]))
            .accessibilityHidden(true)

            // Invisible, NON-dashed 28pt leg hit areas (interactive only).
            if interactive, let onLegTap {
                ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                    if let li = seg.leg {
                        Color.clear
                            .contentShape(MapProjection.hitPath(from: pts[seg.from], to: pts[seg.to]))
                            .onTapGesture { onLegTap(model.legs[li]) }
                            .accessibilityElement()
                            .accessibilityLabel("Leg \(indices[seg.from] + 1) to \(indices[seg.to] + 1)")
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }

            ForEach(Array(pts.enumerated()), id: \.offset) { k, pt in
                let stopIdx = indices[k]
                if model.stops.indices.contains(stopIdx) {
                    let stop = model.stops[stopIdx]
                    pin(number: stop.number)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture { if interactive { onPinTap?(stop.id) } }
                        .allowsHitTesting(interactive && onPinTap != nil)
                        .position(pt)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Stop \(stop.number), \(stop.name)")
                        .accessibilityAddTraits(onPinTap != nil && interactive ? .isButton : [])
                }
            }
        }
    }

    private func pin(number: Int) -> some View {
        Text("\(number)")
            .font(KraftFont.label(13))
            .foregroundStyle(KraftColor.polaroidWhite)
            .frame(width: 26, height: 26)
            .background(Circle().fill(KraftColor.route))
            .overlay(Circle().stroke(KraftColor.polaroidWhite, lineWidth: 1.5))
            .shadow(color: KraftColor.shadow, radius: 1.5, y: 1)
    }

    // MARK: Stop list

    private var stopList: some View {
        let stops = model.stops
        let showAll = stops.count <= 12
        let shown = showAll ? stops : stops.filter { $0.latitude == nil || $0.longitude == nil }
        let cols = (showAll && stops.count > 5) ? 2 : 1
        return VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: cols), alignment: .leading, spacing: 4) {
                ForEach(shown) { s in
                    let off = s.latitude == nil || s.longitude == nil
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(s.number)")
                            .font(KraftFont.label(11))
                            .foregroundStyle(KraftColor.route)
                            .frame(width: 16, alignment: .trailing)
                        Text(s.name).font(KraftFont.note(18)).foregroundStyle(KraftColor.ink).lineLimit(1)
                        if off {
                            Text("not on the map").font(KraftFont.bodyItalic(11)).foregroundStyle(KraftColor.inkSoft)
                                .fixedSize()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Stats strip

/// Typewriter stats band: "4 STOPS · 8.4 KM · 5 H 20 MIN · WALK, TAXI" plus travel time on a second line.
struct OverviewStatsStrip: View {
    var stats: StatsModel

    var body: some View {
        let items = OverviewStatsFormat.items(stats)
        let travel = OverviewStatsFormat.travelText(stats)
        VStack(spacing: 3) {
            ViewThatFits(in: .horizontal) {
                Text(items.joined(separator: " · ")).lineLimit(1).fixedSize()
                Text(items.joined(separator: " · ")).multilineTextAlignment(.center)
            }
            if let travel {
                Text(travel).foregroundStyle(KraftColor.inkSoft)
            }
        }
        .stampLabel()
        .foregroundStyle(KraftColor.ink)
        .frame(maxWidth: .infinity, minHeight: 36)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(KraftColor.paperDeep)
        .overlay(alignment: .top) { dashed }
        .overlay(alignment: .bottom) { dashed }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((items + [travel].compactMap { $0 }).joined(separator: ", "))
    }

    private var dashed: some View {
        Rectangle().stroke(KraftColor.kraftDark, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
    }
}

// MARK: Loader (interactive)

/// Fetches the map snapshot asynchronously (cached on disk), showing the fallback + spinner meanwhile.
struct RouteOverviewPageLoader: View {
    var model: OverviewModel
    var metrics: PageMetrics
    var service: MapSnapshotService = .shared
    var onPinTap: ((String) -> Void)?
    var onLegTap: ((StoryLeg) -> Void)?
    @State private var snap: MapSnap?

    var body: some View {
        RouteOverviewPage(model: model, metrics: metrics, snap: snap, isLoading: snap == nil && hasCoordinates,
                          onPinTap: onPinTap, onLegTap: onLegTap)
            .task(id: model) {
                let size = MapSnapshotService.mapSize(for: metrics)
                snap = await service.snapshot(for: model, size: size, scale: metrics.mode == .print ? 3 : 2)
            }
    }

    private var hasCoordinates: Bool { model.stops.contains { $0.latitude != nil && $0.longitude != nil } }
}

// MARK: Previews

enum OverviewSamples {
    static let leg = { (i: Int, m: String?, km: Double?, min: Int?) in StoryLeg(id: "leg\(i)", modeRaw: m, km: km, minutes: min, story: nil) }
    static let stats = StatsModel(stops: 4, km: 8.4, totalMinutes: 320, travelMinutes: 65, modes: ["walk", "taxi"], photos: 9, moneyText: "₹1,240")

    static let mumbai = OverviewModel(
        stops: [
            OverviewStop(id: "stop-1", number: 1, name: "Chhatrapati Shivaji Terminus", latitude: 18.9398, longitude: 72.8355),
            OverviewStop(id: "stop-2", number: 2, name: "Sardar Pav Bhaji", latitude: 18.9437, longitude: 72.8322),
            OverviewStop(id: "stop-3", number: 3, name: "Hotel Marine Plaza", latitude: 18.9435, longitude: 72.8226),
            OverviewStop(id: "stop-4", number: 4, name: "Siddhivinayak Temple", latitude: 19.0169, longitude: 72.8300),
        ],
        legs: [leg(1, "walk", 0.6, 9), leg(2, "walk", 1.1, 16), leg(3, "taxi", 8.4 - 1.7, 40)],
        stats: stats)

    static let noCoordinates = OverviewModel(
        stops: [
            OverviewStop(id: "stop-1", number: 1, name: "Chhatrapati Shivaji Terminus", latitude: nil, longitude: nil),
            OverviewStop(id: "stop-2", number: 2, name: "Sardar Pav Bhaji", latitude: nil, longitude: nil),
        ],
        legs: [leg(1, "walk", 0.6, 9)], stats: StatsModel(stops: 2, km: 0.6, totalMinutes: 95, travelMinutes: 9, modes: ["walk"], photos: 0, moneyText: nil))

    static let oneStop = OverviewModel(
        stops: [OverviewStop(id: "stop-1", number: 1, name: "Sardar Pav Bhaji", latitude: 18.9437, longitude: 72.8322)],
        legs: [], stats: StatsModel(stops: 1, km: nil, totalMinutes: 45, travelMinutes: 0, modes: [], photos: 2, moneyText: nil))

    static let partial: OverviewModel = {
        var m = mumbai
        m.stops[1].latitude = nil; m.stops[1].longitude = nil
        return m
    }()
}

#Preview("Overview, A4 (live snapshot)") {
    RouteOverviewPageLoader(model: OverviewSamples.mumbai, metrics: .a4)
        .scaleEffect(0.6, anchor: .topLeading).frame(width: 357, height: 505, alignment: .topLeading)
}

#Preview("Overview, phone") {
    ScrollView { RouteOverviewPageLoader(model: OverviewSamples.partial, metrics: .phone(CGSize(width: 390, height: 800)),
                                         onPinTap: { _ in }, onLegTap: { _ in }) }
}

#Preview("No coordinates") {
    RouteOverviewPage(model: OverviewSamples.noCoordinates, metrics: .phone(CGSize(width: 390, height: 800)))
}

#Preview("One stop") {
    RouteOverviewPageLoader(model: OverviewSamples.oneStop, metrics: .phone(CGSize(width: 390, height: 800)))
}
