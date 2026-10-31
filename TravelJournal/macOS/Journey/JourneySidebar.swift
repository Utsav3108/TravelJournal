#if os(macOS)
import SwiftUI

/// Left sidebar: the route map with numbered pins above the stop list. Rows and pins select a stop (centring it in the
/// strip) and highlight together when hovered.
struct JourneySidebar: View {
    @Bindable var model: JourneyWindowModel
    let journey: Journey
    let onAddStop: () -> Void

    @State private var showMapsLocations = false
    @State private var showRoute = false

    /// Space kept free at the bottom of the stop list while the voice card floats over it.
    private static let voiceCardClearance: CGFloat = 230

    var body: some View {
        VStack(spacing: 0) {
            if let overview = model.overview, overview.stops.contains(where: { $0.latitude != nil }) {
                JourneyMapCard(overview: overview, model: model)
                    .padding(12)
            }
            HStack {
                Text("Stops").font(.headline)
                Spacer()
                Button(action: showJourneyRoute) { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath") }
                    .buttonStyle(.borderless)
                    .disabled(model.overview?.stops.isEmpty ?? true)
                    .help("Show route")
                    .accessibilityLabel("Show Route")
                    .accessibilityIdentifier("sidebarShowRoute")
                Button(action: openInMaps) { Image(systemName: "map") }
                    .buttonStyle(.borderless)
                    .disabled(model.overview?.stops.isEmpty ?? true)
                    .help("Open in Maps")
                    .accessibilityLabel("Open in Maps")
                    .accessibilityIdentifier("sidebarOpenInMaps")
                Button(action: onAddStop) { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add a stop")
                    .accessibilityLabel("Add Stop")
                    .accessibilityIdentifier("sidebarAddStop")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            List(selection: selection) {
                ForEach(model.overview?.stops ?? []) { stop in
                    row(stop)
                }
            }
            .listStyle(.sidebar)
            // Room for the voice card, which is drawn as an overlay below so it can't affect the column's layout.
            .contentMargins(.bottom, model.voiceStop == nil ? 0 : Self.voiceCardClearance, for: .scrollContent)
            .overlay {
                if model.overview?.stops.isEmpty ?? true {
                    ContentUnavailableView {
                        Label("No stops yet", systemImage: "mappin.slash")
                    } description: {
                        Text("Add the first stop to start writing your story.")
                    } actions: {
                        Button("Add Stop", action: onAddStop).buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .sheet(isPresented: $showMapsLocations) {
            MapsLocationsSheet(journey: journey, onOpen: MapsLauncher.open).preferredColorScheme(.light)
        }
        .sheet(isPresented: $showRoute) {
            if let overview = model.overview { JourneyRouteSheet(overview: overview).preferredColorScheme(.light) }
        }
        .overlay(alignment: .bottom) {
            if let voice = model.voice, let stop = model.voiceStop {
                VoiceCardView(controller: voice, stop: stop, number: (model.selectedIndex ?? 0) + 1,
                              press: model.voicePress, release: model.voiceRelease)
            }
        }
    }

    private func showJourneyRoute() {
        guard let overview = model.overview else { return }
        switch JourneyMapsLogic.readiness(for: overview) {
        case .ready: showRoute = true
        case .needsLocations: showMapsLocations = true
        }
    }

    private func openInMaps() {
        guard let overview = model.overview else { return }
        switch JourneyMapsLogic.readiness(for: overview) {
        case .ready(let pins): MapsLauncher.open(pins)
        case .needsLocations: showMapsLocations = true
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { model.selectedStopID }, set: { model.select($0) })
    }

    private func row(_ stop: OverviewStop) -> some View {
        let id = StripComposer.stopID(ofPageID: stop.id)
        return HStack(spacing: 10) {
            Text("\(stop.number)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(KraftColor.paper)
                .frame(width: 20, height: 20)
                .background(Circle().fill(KraftColor.route))
                .accessibilityHidden(true)
            Text(stop.name.isEmpty ? "Untitled stop" : stop.name).lineLimit(2)
        }
        .tag(id)
        .onHover { model.hover(id, isInside: $0) }
        .listRowBackground(model.hoveredStopID == id ? KraftColor.route.opacity(0.12) : nil)
        .accessibilityLabel("Stop \(stop.number), \(stop.name)")
    }
}

/// Map snapshot (cached by `MapSnapshotService`, drawn fallback when offline) with a dashed route and numbered pins.
private struct JourneyMapCard: View {
    let overview: OverviewModel
    @Bindable var model: JourneyWindowModel

    @Environment(\.displayScale) private var displayScale
    @State private var snap: MapSnap?

    private static let minimumMapWidth = 100

    private struct SnapshotKey: Hashable {
        var stops: [OverviewStop]
        var width: Int
    }

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: max(geo.size.width, 1), height: max(geo.size.height, 1))
            // Snap the width so dragging the sidebar edge doesn't request a new map on every point.
            let key = SnapshotKey(stops: overview.stops, width: Int(size.width / 20) * 20)
            ZStack(alignment: .topLeading) {
                if let snap {
                    Image(texture: snap.image, scale: snap.scale).resizable().frame(width: size.width, height: size.height)
                    pins(snap, in: size)
                } else {
                    KraftColor.paperDeep
                    ProgressView().controlSize(.small).frame(width: size.width, height: size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: key) {
                // The first layout pass can report a sliver of a width; a map requested at that size is a thumbnail
                // that would be stretched over the whole card.
                guard key.width >= Self.minimumMapWidth else { return }
                // Wait out window zoom/resize animations: each intermediate width would otherwise start its own
                // snapshot, and a stale small one can finish last. `.task(id:)` cancels this sleep on the next width.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let request = CGSize(width: CGFloat(key.width), height: CGFloat(key.width) / 1.25)
                let result = await MapSnapshotService.shared.snapshot(for: overview, size: request, scale: displayScale)
                // A superseded request can still finish after the current one; it must not replace the better map.
                guard !Task.isCancelled else { return }
                snap = result
            }
        }
        .aspectRatio(1.25, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Route map")
    }

    @ViewBuilder private func pins(_ snap: MapSnap, in size: CGSize) -> some View {
        let sx = size.width / max(snap.size.width, 1), sy = size.height / max(snap.size.height, 1)
        let pts = snap.pins.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        let indices = snap.stopIndices.count == pts.count ? snap.stopIndices : Array(pts.indices)
        Path { p in
            for (i, pt) in pts.enumerated() { if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) } }
        }
        .stroke(KraftColor.route.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))
        .allowsHitTesting(false)
        ForEach(Array(pts.enumerated()), id: \.offset) { k, pt in
            if overview.stops.indices.contains(indices[k]) {
                let stop = overview.stops[indices[k]]
                pin(stop, at: pt)
            }
        }
    }

    private func pin(_ stop: OverviewStop, at point: CGPoint) -> some View {
        let id = StripComposer.stopID(ofPageID: stop.id)
        let active = model.selectedStopID == id, hovered = model.hoveredStopID == id
        let diameter: CGFloat = active || hovered ? 26 : 20
        return Text("\(stop.number)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(KraftColor.paper)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(active ? KraftColor.ink : KraftColor.route))
            .overlay(Circle().strokeBorder(KraftColor.paper, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .position(point)
            .animation(.easeOut(duration: 0.12), value: diameter)
            .onTapGesture { model.select(id) }
            .onHover { model.hover(id, isInside: $0) }
            .accessibilityLabel("Stop \(stop.number), \(stop.name)")
            .accessibilityAddTraits(.isButton)
    }
}
#endif
