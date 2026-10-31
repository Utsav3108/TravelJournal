#if os(macOS)
import MapKit
import CoreLocation

/// Hands a journey's pins to the Maps app: start, stops and end, each labelled, framed to fit.
enum MapsLauncher {
    @MainActor
    static func open(_ pins: [MapsPin]) {
        let items = pins.map { pin in item(JourneyMapsLogic.label(for: pin), pin.latitude, pin.longitude) }
        MKMapItem.openMaps(with: items, launchOptions: nil)
    }

    /// One leg with Apple's turn-by-turn for its mode. Modes Maps can't route (ferry) open the two stops as pins.
    @MainActor
    static func openLeg(fromName: String, from: Coordinate, toName: String, to: Coordinate, mode: TransportMode) {
        let items = [item(fromName, from.latitude, from.longitude), item(toName, to.latitude, to.longitude)]
        guard case .directions(let transport) = LegRouting.strategy(for: mode) else {
            MKMapItem.openMaps(with: items, launchOptions: nil)
            return
        }
        MKMapItem.openMaps(with: items, launchOptions: [MKLaunchOptionsDirectionsModeKey: directionsMode(transport)])
    }

    private static func item(_ name: String, _ lat: Double, _ lon: Double) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
        item.name = name
        return item
    }

    private static func directionsMode(_ transport: MapsTransport) -> String {
        switch transport {
        case .driving: MKLaunchOptionsDirectionsModeDriving
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .cycling: MKLaunchOptionsDirectionsModeCycling
        }
    }
}
#endif
