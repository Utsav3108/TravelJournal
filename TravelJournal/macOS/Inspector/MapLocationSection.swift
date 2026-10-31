#if os(macOS)
import SwiftUI
import SwiftData

/// "Map location" in the cover editor: which stop is pinned on the story's map, and where that stop is. Searching for a
/// place writes to the stop itself, so the stop, the map and the exports stay in sync.
struct MapLocationSection: View {
    @Bindable var journey: Journey

    var body: some View {
        let choices = MapStopChoices.choices(for: journey)
        if let stop = MapStopChoices.selectedStop(for: journey) {
            Section("Map location") {
                Picker("Stop", selection: Binding(get: { stop.id }, set: { journey.mapStopID = $0 })) {
                    ForEach(choices) { Text($0.label).tag($0.id) }
                }
                .accessibilityIdentifier("mapStopPicker")
            }
            MapStopLocation(stop: stop).id(stop.id)
        }
    }
}

private struct MapStopLocation: View {
    let stop: Stop
    @State private var showPlaceSearch = false

    var body: some View {
        StopLocationSection(stop: stop, showPlaceSearch: $showPlaceSearch,
                            hint: MapStopChoices.hint(latitude: stop.latitude, longitude: stop.longitude))
            .sheet(isPresented: $showPlaceSearch) {
                PlaceSearchSheet(stop: stop).preferredColorScheme(.light)
            }
            .undoTracked(StopContent(stop), target: stop) { $0.apply(to: stop) }
    }
}
#endif
