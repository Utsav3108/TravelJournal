import Foundation
import MapKit
import CoreLocation
import SwiftUI

// MARK: Backend abstraction (fakeable in tests)

nonisolated protocol PlaceBackend: Sendable {
    func pointsOfInterest(latitude: Double, longitude: Double, radius: Double) async throws -> [PlaceCandidate]
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceCandidate?
    func search(_ query: String, centerLatitude: Double?, centerLongitude: Double?) async throws -> [PlaceCandidate]
}

// MARK: Throttled, cached lookup

/// Serial (actor) lookup with min spacing between backend calls, exponential backoff on error, and a
/// coordinate cache (4 decimals ~ 11 m). Errors/offline never throw: nil / [] is returned.
actor ThrottledPlaceLookup: PlaceLookup {
    private let backend: PlaceBackend
    private let minInterval: TimeInterval
    private let maxRetries: Int
    private let radius: Double
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var lastCall: Date?
    private var cache: [String: PlaceCandidate?] = [:]

    init(backend: PlaceBackend,
         minInterval: TimeInterval = 1.0,
         maxRetries: Int = 2,
         radius: Double = 150,
         sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.backend = backend
        self.minInterval = minInterval
        self.maxRetries = maxRetries
        self.radius = radius
        self.sleep = sleep
    }

    nonisolated static func cacheKey(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.4f,%.4f", lat, lon)
    }

    var cachedCount: Int { cache.count }

    func place(near latitude: Double, longitude: Double) async -> PlaceCandidate? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let key = Self.cacheKey(latitude, longitude)
        if let hit = cache[key] { return hit }

        do {
            let r = radius
            let b = backend
            let pois = try await throttled { try await b.pointsOfInterest(latitude: latitude, longitude: longitude, radius: r) }
            if let best = Self.nearest(pois, latitude: latitude, longitude: longitude, within: radius) {
                cache[key] = .some(best)
                return best
            }
            let rev = try await throttled { try await b.reverseGeocode(latitude: latitude, longitude: longitude) }
            cache[key] = .some(rev)   // genuine "nothing found" is cached too; errors are not
            return rev
        } catch {
            return nil
        }
    }

    func search(_ query: String, nearLatitude: Double?, nearLongitude: Double?) async -> [PlaceCandidate] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let b = backend
        return (try? await throttled { try await b.search(q, centerLatitude: nearLatitude, centerLongitude: nearLongitude) }) ?? []
    }

    nonisolated static func nearest(_ items: [PlaceCandidate], latitude: Double, longitude: Double, within meters: Double) -> PlaceCandidate? {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        return items
            .map { ($0, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) }
            .filter { $0.1 <= meters }
            .min { $0.1 < $1.1 }?.0
    }

    private func throttled<T: Sendable>(_ op: @Sendable () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            if let last = lastCall {
                let wait = minInterval - Date().timeIntervalSince(last)
                if wait > 0 { await sleep(wait) }
            }
            lastCall = Date()
            do { return try await op() }
            catch {
                if Task.isCancelled || attempt >= maxRetries { throw error }
                attempt += 1
                await sleep(minInterval * pow(2, Double(attempt)))   // 2s, 4s with default spacing
                lastCall = Date()
            }
        }
    }
}

// MARK: MapKit backend

nonisolated struct MapKitPlaceBackend: PlaceBackend {
    func pointsOfInterest(latitude: Double, longitude: Double, radius: Double) async throws -> [PlaceCandidate] {
        let req = MKLocalPointsOfInterestRequest(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), radius: radius)
        req.pointOfInterestFilter = .includingAll
        let resp = try await MKLocalSearch(request: req).start()
        return await MainActor.run { resp.mapItems.compactMap(Self.candidate) }
    }

    func reverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceCandidate? {
        // MKReverseGeocodingRequest (iOS 26+) replaces the deprecated CLGeocoder; init is failable.
        guard let req = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)) else { return nil }
        let items = try await req.mapItems
        return await MainActor.run {
            guard let item = items.first else { return nil }
            if let c = Self.candidate(item) { return c }
            // Area-only: use short address or city as the name.
            let name = item.address?.shortAddress ?? item.addressRepresentations?.cityName ?? item.address?.fullAddress
            guard let name, !name.isEmpty else { return nil }
            return PlaceCandidate(name: name, address: item.address?.fullAddress,
                                  city: item.addressRepresentations?.cityName,
                                  latitude: latitude, longitude: longitude)
        }
    }

    func search(_ query: String, centerLatitude: Double?, centerLongitude: Double?) async throws -> [PlaceCandidate] {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        if let la = centerLatitude, let lo = centerLongitude {
            req.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: la, longitude: lo),
                                            latitudinalMeters: 15_000, longitudinalMeters: 15_000)
        }
        req.resultTypes = [.pointOfInterest, .address]
        let resp = try await MKLocalSearch(request: req).start()
        return await MainActor.run { resp.mapItems.compactMap(Self.candidate) }
    }

    @MainActor
    private static func candidate(_ item: MKMapItem) -> PlaceCandidate? {
        let c = item.location.coordinate
        guard CLLocationCoordinate2DIsValid(c), let name = item.name, !name.isEmpty else { return nil }
        return PlaceCandidate(name: name,
                              address: item.address?.fullAddress,
                              city: item.addressRepresentations?.cityName,
                              latitude: c.latitude, longitude: c.longitude)
    }
}

/// Production PlaceLookup: nearby POI (~150 m) -> reverse geocode -> nil; MKLocalSearch for text.
final class MapKitPlaceLookup: PlaceLookup, Sendable {
    private let inner: ThrottledPlaceLookup
    init() { inner = ThrottledPlaceLookup(backend: MapKitPlaceBackend()) }

    func place(near latitude: Double, longitude: Double) async -> PlaceCandidate? {
        await inner.place(near: latitude, longitude: longitude)
    }
    func search(_ query: String, nearLatitude: Double?, nearLongitude: Double?) async -> [PlaceCandidate] {
        await inner.search(query, nearLatitude: nearLatitude, nearLongitude: nearLongitude)
    }
}

/// For previews and tests.
struct NoopPlaceLookup: PlaceLookup {
    init() {}
    func place(near latitude: Double, longitude: Double) async -> PlaceCandidate? { nil }
    func search(_ query: String, nearLatitude: Double?, nearLongitude: Double?) async -> [PlaceCandidate] { [] }
}

// MARK: Environment

private struct ServicePlaceLookupKey: EnvironmentKey {
    static let defaultValue: any PlaceLookup = NoopPlaceLookup()
}

extension EnvironmentValues {
    var servicePlaceLookup: any PlaceLookup {
        get { self[ServicePlaceLookupKey.self] }
        set { self[ServicePlaceLookupKey.self] = newValue }
    }
}
