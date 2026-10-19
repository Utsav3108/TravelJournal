import Foundation
import UIKit

/// Fallbacks used when no real service is injected: return nothing.
struct EmptyPhotoImporter: PhotoImporting {
    func importItems(_ items: [AnyHashable]) async -> [PhotoMeta] { [] }
}

struct EmptyPlaceLookup: PlaceLookup {
    func place(near latitude: Double, longitude: Double) async -> PlaceCandidate? { nil }
    func search(_ query: String, nearLatitude: Double?, nearLongitude: Double?) async -> [PlaceCandidate] { [] }
}

/// Returns a fixed list of photos regardless of what was picked.
struct MockPhotoImporter: PhotoImporting {
    var photos: [PhotoMeta]
    var delay: Duration = .zero
    func importItems(_ items: [AnyHashable]) async -> [PhotoMeta] {
        if delay > .zero { try? await Task.sleep(for: delay) }
        return photos
    }
}

/// Resolves the Mumbai fixture places by proximity (300 m), searches them by name.
struct MockPlaceLookup: PlaceLookup {
    var delay: Duration = .zero
    func place(near latitude: Double, longitude: Double) async -> PlaceCandidate? {
        if delay > .zero { try? await Task.sleep(for: delay) }
        return MumbaiFixtures.Place.allCases
            .map { ($0, Geo.haversine(latitude, longitude, $0.latitude, $0.longitude)) }
            .filter { $0.1 <= 300 }
            .min { $0.1 < $1.1 }?.0.candidate
    }
    func search(_ query: String, nearLatitude: Double?, nearLongitude: Double?) async -> [PlaceCandidate] {
        let q = query.lowercased()
        return MumbaiFixtures.Place.allCases.filter { $0.name.lowercased().contains(q) }.map(\.candidate)
    }
}

/// Mumbai day-trip fixtures (19 Oct 2026, IST) for previews and tests.
enum MumbaiFixtures {
    enum Place: CaseIterable {
        case cst, pavBhaji, siddhivinayak, hotel
        var name: String {
            switch self {
            case .cst: "Chhatrapati Shivaji Terminus"
            case .pavBhaji: "Sardar Pav Bhaji"
            case .siddhivinayak: "Siddhivinayak Temple"
            case .hotel: "Hotel Marine Plaza"
            }
        }
        var latitude: Double {
            switch self { case .cst: 18.9398; case .pavBhaji: 18.9712; case .siddhivinayak: 19.0169; case .hotel: 19.0176 }
        }
        var longitude: Double {
            switch self { case .cst: 72.8355; case .pavBhaji: 72.8113; case .siddhivinayak: 72.8301; case .hotel: 72.8562 }
        }
        var candidate: PlaceCandidate {
            PlaceCandidate(name: name, address: "Mumbai, Maharashtra", city: "Mumbai", latitude: latitude, longitude: longitude)
        }
    }

    static let ist = TimeZone(secondsFromGMT: 19_800)!
    static func date(_ h: Int, _ m: Int, day: Int = 19) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = ist
        return c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    /// Roughly `meters` north of a latitude.
    static func north(_ lat: Double, _ meters: Double) -> Double { lat + meters / 111_320 }

    static func photo(_ id: String, _ place: Place?, _ h: Int?, _ m: Int = 0,
                      latOffsetMeters: Double = 0, jpeg: Data = Data()) -> PhotoMeta {
        PhotoMeta(id: id,
                  date: h.map { date($0, m) },
                  latitude: place.map { north($0.latitude, latOffsetMeters) },
                  longitude: place?.longitude,
                  jpegData: jpeg)
    }

    /// A small real JPEG (flat colour with a lighter band) for previews and photo-store tests.
    static func jpeg(seed: Int = 0, size: CGSize = CGSize(width: 480, height: 360)) -> Data {
        let hue = CGFloat((seed * 37) % 100) / 100
        let r = UIGraphicsImageRenderer(size: size)
        return r.jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 1, alpha: 0.35).setFill()
            ctx.fill(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.2))
        }
    }

    /// 3 at CST, 4 at pav bhaji, 3 at the temple, 2 at the hotel, plus one photo with nothing.
    static func dayTrip(withJPEG: Bool = true, includeUnplaced: Bool = true) -> [PhotoMeta] {
        var out: [PhotoMeta] = []
        var n = 0
        func add(_ place: Place, _ times: [(Int, Int)]) {
            for t in times {
                n += 1
                out.append(photo("p\(n)", place, t.0, t.1, jpeg: withJPEG ? jpeg(seed: n) : Data()))
            }
        }
        add(.cst, [(9, 0), (9, 5), (9, 10)])
        add(.pavBhaji, [(11, 30), (11, 40), (11, 50), (12, 0)])
        add(.siddhivinayak, [(14, 0), (14, 10), (14, 20)])
        add(.hotel, [(17, 0), (17, 5)])
        if includeUnplaced { out.append(photo("bare", nil, nil, jpeg: withJPEG ? jpeg(seed: 99) : Data())) }
        return out
    }
}
