#if os(macOS)
import SwiftUI
import MapKit

/// The whole journey on one map, each leg drawn in its own mode's style. Lines appear straight at once and are
/// replaced by real roads as directions come back. Apple Maps can't show mixed modes, so this is drawn here;
/// each leg can still be opened in Maps for turn-by-turn.
struct JourneyRouteSheet: View {
    let overview: OverviewModel

    @Environment(\.dismiss) private var dismiss
    @State private var service = LegRouteService()
    @State private var routes: [String: [Coordinate]] = [:]
    @State private var position: MapCameraPosition = .automatic

    private var segments: [LegSegment] { LegRouting.segments(for: overview) }
    private var pins: [MapsPin] { JourneyMapsLogic.pins(from: overview) }
    private var names: [String: String] {
        Dictionary(uniqueKeysWithValues: overview.stops.map { ($0.id, $0.name.isEmpty ? "Stop \($0.number)" : $0.name) })
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                ForEach(segments) { segment in
                    let style = LegRouting.style(for: segment.mode)
                    MapPolyline(coordinates: (routes[segment.id] ?? [segment.from, segment.to]).map(\.location))
                        .stroke(Self.color(style.colorToken),
                                style: StrokeStyle(lineWidth: style.width, lineCap: .round, dash: style.dash))
                }
                ForEach(Array(pins.enumerated()), id: \.offset) { _, pin in
                    Marker(JourneyMapsLogic.label(for: pin), systemImage: "mappin",
                           coordinate: pin.coordinate)
                        .tint(KraftColor.route)
                }
            }
            .frame(minHeight: 340)
            Divider()
            List(segments) { segment in
                HStack {
                    Image(systemName: Self.symbol(segment.mode)).frame(width: 22)
                        .foregroundStyle(Self.color(LegRouting.style(for: segment.mode).colorToken))
                        .accessibilityHidden(true)
                    Text("\(names[segment.fromStopID] ?? "") → \(names[segment.toStopID] ?? "")").lineLimit(1)
                    Spacer()
                    Button("Open in Maps") {
                        MapsLauncher.openLeg(fromName: names[segment.fromStopID] ?? "", from: segment.from,
                                             toName: names[segment.toStopID] ?? "", to: segment.to, mode: segment.mode)
                    }
                }
            }
            .frame(height: 150)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 760, height: 620)
        .task(id: segments.map(\.id)) {
            fit()
            for await (segment, points) in service.routes(for: segments) { routes[segment.id] = points }
        }
    }

    private func fit() {
        let points = segments.flatMap { [$0.from, $0.to] }.map(\.location)
        if let region = StoryMapLogic.region(fitting: points) { position = .region(region) }
    }

    private static func color(_ token: String) -> Color {
        switch token {
        case "stampTeal": KraftColor.stampTeal
        case "kraftDark": KraftColor.kraftDark
        default: KraftColor.route
        }
    }

    private static func symbol(_ mode: TransportMode) -> String {
        switch mode {
        case .walk: "figure.walk"
        case .autoRickshaw, .taxi: "car.fill"
        case .bus: "bus.fill"
        case .localTrain, .metro: "tram.fill"
        case .bike: "bicycle"
        case .ferry: "ferry.fill"
        }
    }
}

private extension Coordinate {
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

private extension MapsPin {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
#endif
