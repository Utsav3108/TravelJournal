#if os(macOS)
import SwiftUI
import SwiftData
import MapKit

/// Full-window map of every story that has a located map stop. One pin per place; a pin shared by several
/// stories opens a list to pick from.
struct StoryMapView: View {
    @Environment(\.openJourney) private var openJourney
    @Query(sort: \Journey.date, order: .reverse) private var journeys: [Journey]
    @State private var position: MapCameraPosition = .automatic

    private var pins: [StoryPin] { StoryMapPins.pins(for: journeys) }

    var body: some View {
        Group {
            if pins.isEmpty {
                ContentUnavailableView("No places yet", systemImage: "map",
                                       description: Text("Add a location to a story's map stop to see it here"))
            } else {
                Map(position: $position) {
                    ForEach(pins) { pin in
                        Annotation("", coordinate: pin.coordinate) {
                            StoryPinMarker(pin: pin, journeys: journeys, open: open)
                        }
                    }
                }
                .onAppear(perform: fitCamera)
            }
        }
        .navigationTitle("Map")
        .onChange(of: pins.map(\.id)) { fitCamera() }
    }

    private func fitCamera() {
        if let region = StoryMapLogic.region(fitting: pins.map(\.coordinate)) { position = .region(region) }
    }

    private func open(_ id: UUID) {
        guard let journey = journeys.first(where: { $0.id == id }) else { return }
        openJourney?(journey)
    }
}

private struct StoryPinMarker: View {
    let pin: StoryPin
    let journeys: [Journey]
    let open: (UUID) -> Void
    @State private var showList = false

    var body: some View {
        Button {
            if pin.journeyIDs.count == 1, let id = pin.journeyIDs.first { open(id) } else { showList = true }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                if pin.journeyIDs.count > 1 {
                    Text("\(pin.journeyIDs.count)").font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 5).background(.black, in: Capsule()).offset(x: 8, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showList) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(StoryMapLogic.rows(for: pin.journeyIDs, in: journeys)) { row in
                    Button { showList = false; open(row.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayTitle).font(.body)
                            Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 240).padding(.vertical, 4)
        }
    }
}
#endif
