import SwiftUI
import MapKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Builds the sepia/paper route map. `snapshot(for:size:)` never throws: any failure (offline,
/// timeout, no coordinates) yields the illustrated fallback, so callers (viewer, PDF exporter) can
/// simply await it BEFORE rendering. Successful snapshots are cached on disk so the page keeps
/// working offline after the first load.
@MainActor
final class MapSnapshotService {
    static let shared = MapSnapshotService()

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var memory: [String: MapSnap] = [:]
    /// Recent snapshot failures (offline etc.): skip the network attempt for a short while so pages and exports don't each wait out the timeout.
    private var failedAt: [String: Date] = [:]
    private let retryAfter: TimeInterval = 60
    private let cacheDir: URL
    var timeout: Duration = .seconds(10)

    init(cacheDirectory: URL? = nil) {
        cacheDir = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("RouteMaps", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Standard map card size for a page.
    nonisolated static func mapSize(for metrics: PageMetrics) -> CGSize {
        let w = max(metrics.size.width - 2 * metrics.margin - 12, 100)   // minus 6pt frame each side
        let h = metrics.mode == .print ? 400 : min(260, w * 0.76)
        return CGSize(width: w, height: h)
    }

    nonisolated static func geoPoints(of model: OverviewModel) -> (points: [GeoPoint], stopIndices: [Int]) {
        var pts: [GeoPoint] = [], idx: [Int] = []
        for (i, s) in model.stops.enumerated() {
            if let la = s.latitude, let lo = s.longitude { pts.append(GeoPoint(lat: la, lon: lo)); idx.append(i) }
        }
        return (pts, idx)
    }

    func snapshot(for model: OverviewModel, size: CGSize, scale: CGFloat = 2) async -> MapSnap {
        let (pts, idx) = Self.geoPoints(of: model)
        return await snapshot(points: pts, stopIndices: idx, size: size, scale: scale)
    }

    func snapshot(points: [GeoPoint], stopIndices: [Int]? = nil, size: CGSize, scale: CGFloat = 2) async -> MapSnap {
        let idx = stopIndices ?? Array(points.indices)
        guard !points.isEmpty else { return Self.fallback(points: points, stopIndices: idx, size: size) }
        let key = MapProjection.cacheKey(points, size: size, scale: scale)
        if let hit = memory[key] { return hit }
        if let hit = loadFromDisk(key: key, points: points, stopIndices: idx, size: size, scale: scale) {
            memory[key] = hit
            return hit
        }
        if let t = failedAt[key], Date().timeIntervalSince(t) < retryAfter {
            return Self.fallback(points: points, stopIndices: idx, size: size)
        }
        do {
            let snap = try await withThrowingTaskGroup(of: MapSnap.self) { group in
                group.addTask { @MainActor in try await self.takeSnapshot(points: points, stopIndices: idx, size: size, scale: scale) }
                group.addTask { @MainActor in
                    try await Task.sleep(for: self.timeout)
                    throw CancellationError()
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            memory[key] = snap
            failedAt[key] = nil
            saveToDisk(snap, key: key)
            return snap
        } catch {
            failedAt[key] = Date()
            return Self.fallback(points: points, stopIndices: idx, size: size)
        }
    }

    /// Illustrated fallback with pins laid out proportionally. Synchronous (no network).
    static func fallback(for model: OverviewModel, size: CGSize) -> MapSnap {
        let (pts, idx) = geoPoints(of: model)
        return fallback(points: pts, stopIndices: idx, size: size)
    }

    static func fallback(points: [GeoPoint], stopIndices: [Int], size: CGSize) -> MapSnap {
        let seed = MapProjection.cacheKey(points, size: size, scale: 1)
        let scale = IllustratedMapFallback.defaultScale
        return MapSnap(image: IllustratedMapFallback.render(size: size, seed: seed, scale: scale), scale: scale,
                       pins: MapProjection.fallbackPoints(points, size: size),
                       size: size, stopIndices: stopIndices, isFallback: true)
    }

    // MARK: MapKit

    private func takeSnapshot(points: [GeoPoint], stopIndices: [Int], size: CGSize, scale: CGFloat) async throws -> MapSnap {
        guard let r = MapProjection.fitRegion(points, aspect: size.width / size.height) else { throw CancellationError() }
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: r.centerLat, longitude: r.centerLon),
                                      span: MKCoordinateSpan(latitudeDelta: r.latSpan, longitudeDelta: r.lonSpan))
        o.size = size
        MapKitImageEdge.request(scale: scale, on: o)
        o.mapType = .mutedStandard
        o.showsBuildings = false
        o.pointOfInterestFilter = .excludingAll
        MapKitImageEdge.forceLight(o)
        let snap = try await MKMapSnapshotter(options: o).start()
        let pins = points.map { snap.point(for: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)) }
        // Sanity: a blank/throttled snapshot has no usable pixels.
        guard let raw = MapKitImageEdge.cgImage(from: snap) else { throw CancellationError() }
        let actualScale = MapKitImageEdge.pixelScale(of: raw, forPointWidth: size.width)
        guard CGFloat(raw.width) / actualScale > 1 else { throw CancellationError() }
        let tinted = paperTint(raw)
        return MapSnap(image: tinted, scale: actualScale, pins: pins, size: size, stopIndices: stopIndices, isFallback: false)
    }

    // MARK: Sepia / paper pass

    /// kraft monochrome -> multiply paper -> grain -> vignette. Image in, image out.
    func paperTint(_ image: CGImage) -> CGImage {
        let input = CIImage(cgImage: image)
        let extent = input.extent

        let mono = CIFilter.colorMonochrome()
        mono.inputImage = input
        mono.color = CIColor(red: 0.55, green: 0.42, blue: 0.28)
        mono.intensity = 0.95

        let controls = CIFilter.colorControls()
        controls.inputImage = mono.outputImage
        controls.saturation = 0.85
        controls.contrast = 1.05
        controls.brightness = 0.09

        let paper = CIImage(color: CIColor(red: 0xF3 / 255, green: 0xEB / 255, blue: 0xDD / 255)).cropped(to: extent)
        let multiply = CIFilter.multiplyBlendMode()
        multiply.inputImage = controls.outputImage
        multiply.backgroundImage = paper
        var out = multiply.outputImage ?? input

        do {
            // 1x tile: the grain is laid over snapshot PIXELS, so its size is deliberately independent of the display scale.
            let grain = CIImage(cgImage: PaperGrain.tile(scale: 1))
                .applyingFilter("CIAffineTile")
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.6)])
                .cropped(to: extent)
            out = grain.composited(over: out)
        }

        let vignette = CIFilter.vignette()
        vignette.inputImage = out
        vignette.intensity = 0.15
        vignette.radius = Float(max(extent.width, extent.height) / 70)
        out = vignette.outputImage ?? out

        guard let result = ciContext.createCGImage(out.cropped(to: extent), from: extent) else { return image }
        return result
    }

    // MARK: Disk cache (image PNG + pins JSON)

    private struct Meta: Codable { var pins: [[Double]]; var stopIndices: [Int] }

    private func loadFromDisk(key: String, points: [GeoPoint], stopIndices: [Int], size: CGSize, scale: CGFloat) -> MapSnap? {
        let png = cacheDir.appendingPathComponent("\(key).png"), meta = cacheDir.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: png),
              let img = ImageDecoding.cgImage(from: data, maxPixel: Int((max(size.width, size.height) * scale).rounded(.up))),
              let m = try? JSONDecoder().decode(Meta.self, from: Data(contentsOf: meta)),
              m.pins.count == points.count else { return nil }
        return MapSnap(image: img, scale: scale, pins: m.pins.map { CGPoint(x: $0[0], y: $0[1]) }, size: size, stopIndices: stopIndices, isFallback: false)
    }

    private func saveToDisk(_ snap: MapSnap, key: String) {
        guard let data = ImageDrawing.pngData(snap.image) else { return }
        try? data.write(to: cacheDir.appendingPathComponent("\(key).png"), options: .atomic)
        let meta = Meta(pins: snap.pins.map { [Double($0.x), Double($0.y)] }, stopIndices: snap.stopIndices)
        if let j = try? JSONEncoder().encode(meta) { try? j.write(to: cacheDir.appendingPathComponent("\(key).json"), options: .atomic) }
    }

    func clearCache() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}
