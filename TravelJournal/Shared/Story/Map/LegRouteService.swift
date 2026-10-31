import Foundation
import MapKit

/// Source of road/path geometry for a hop. Tests use a fake.
nonisolated protocol LegDirectionsBackend: Sendable {
    func route(from: Coordinate, to: Coordinate, transport: MapsTransport) async throws -> [Coordinate]
}

/// MKDirections-backed geometry. Apple only supports `.transit` for ETAs, so transit
/// requests normally throw and the service falls back to a straight line.
nonisolated struct MapKitDirectionsBackend: LegDirectionsBackend {
    func route(from: Coordinate, to: Coordinate, transport: MapsTransport) async throws -> [Coordinate] {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = switch transport {
        case .driving: .automobile
        case .walking: .walking
        case .transit: .transit
        case .cycling: .cycling
        }
        let response = try await MKDirections(request: request).calculate()
        guard let polyline = response.routes.first?.polyline else { return [] }
        let points = polyline.points()
        return (0..<polyline.pointCount).map {
            let c = points[$0].coordinate
            return Coordinate(latitude: c.latitude, longitude: c.longitude)
        }
    }
}

/// Resolves segments to polylines, caching results and coalescing identical in-flight requests.
@MainActor
final class LegRouteService {
    private struct Key: Hashable { var from: Coordinate; var to: Coordinate; var transport: MapsTransport }

    private let backend: LegDirectionsBackend
    private let maxConcurrent: Int
    private var cache: [Key: [Coordinate]] = [:]
    private var inFlight: [Key: Task<[Coordinate], Never>] = [:]

    init(backend: LegDirectionsBackend = MapKitDirectionsBackend(), maxConcurrent: Int = 3) {
        self.backend = backend
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// Polyline for one segment; a straight `[from, to]` line when routing is not possible.
    func route(for segment: LegSegment) async -> [Coordinate] {
        let straight = [segment.from, segment.to]
        guard case .directions(let transport) = LegRouting.strategy(for: segment.mode) else { return straight }
        let key = Key(from: segment.from, to: segment.to, transport: transport)
        if let hit = cache[key] { return hit }
        if let task = inFlight[key] { return await task.value }
        let backend = backend
        let task = Task<[Coordinate], Never> {
            guard let line = try? await backend.route(from: key.from, to: key.to, transport: transport),
                  line.count >= 2 else { return straight }
            return line
        }
        inFlight[key] = task
        let line = await task.value
        inFlight[key] = nil
        cache[key] = line
        return line
    }

    /// Yields each segment's polyline as it resolves (at most `maxConcurrent` at a time).
    /// A UI can draw straight lines first, then replace them as results arrive.
    func routes(for segments: [LegSegment]) -> AsyncStream<(LegSegment, [Coordinate])> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                await withTaskGroup(of: (LegSegment, [Coordinate]).self) { group in
                    var next = 0
                    func addNext() {
                        guard next < segments.count else { return }
                        let seg = segments[next]; next += 1
                        group.addTask { @MainActor in (seg, await self.route(for: seg)) }
                    }
                    for _ in 0..<min(maxConcurrent, segments.count) { addNext() }
                    while let result = await group.next() {
                        continuation.yield(result)
                        addNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
