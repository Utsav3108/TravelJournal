#if os(macOS)
import SwiftUI

/// Shown when fewer than two stops have a location. Lists every stop so the user can add or change locations, and
/// enables "Open in Maps" as soon as two are set. "Find this place" writes to the stop itself.
struct MapsLocationsSheet: View {
    let journey: Journey
    let onOpen: ([MapsPin]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searching: Stop?

    private var stops: [Stop] { journey.orderedStops }

    private var readiness: JourneyMapsLogic.Readiness {
        JourneyMapsLogic.readiness(forStops: stops.enumerated().map { i, s in
            OverviewStop(id: s.id.uuidString, number: i + 1, name: s.placeName,
                         latitude: s.latitude, longitude: s.longitude)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add locations to at least two stops to see your journey in Maps.")
                .font(.headline)
            List(stops) { stop in
                HStack {
                    Image(systemName: stop.coordinate == nil ? "mappin.slash" : "mappin.circle.fill")
                        .foregroundStyle(stop.coordinate == nil ? KraftColor.inkSoft : KraftColor.route)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(stop.placeName.isEmpty ? "Untitled stop" : stop.placeName)
                        if let lat = stop.latitude, let lon = stop.longitude {
                            Text(String(format: "%.4f, %.4f", lat, lon)).font(.footnote).foregroundStyle(KraftColor.inkSoft)
                        } else {
                            Text("No location yet").font(.footnote).foregroundStyle(KraftColor.inkSoft)
                        }
                    }
                    Spacer()
                    Button(stop.coordinate == nil ? "Find this place" : "Change") { searching = stop }
                }
            }
            .frame(minHeight: 200)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Open in Maps") {
                    if case .ready(let pins) = readiness { onOpen(pins); dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled({ if case .ready = readiness { false } else { true } }())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 380)
        .sheet(item: $searching) { stop in
            PlaceSearchSheet(stop: stop).preferredColorScheme(.light)
        }
    }
}
#endif
