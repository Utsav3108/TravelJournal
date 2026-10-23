import Foundation
import CoreGraphics
import SwiftData
@testable import TravelJournal

/// Deterministic journeys for composer, privacy and snapshot tests, built in an in-memory store.
/// Photos carry real, photo-like JPEG bytes at the stored display size (long edge `PhotoLimits.displayMaxPixel`),
/// so PDF size tests are meaningful. Same inputs give the same content (ids aside) and byte-identical images.
@MainActor
enum JourneyFixtures {
    /// Keeps the container alive alongside the journey (a context alone does not retain its store).
    @MainActor
    struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let journey: Journey

        var stops: [Stop] { journey.orderedStops }
        var snapshot: JourneySnapshot { JourneySnapshot(journey: journey) }
    }

    /// One stop's recipe.
    struct StopSpec {
        var name: String
        var category: StopCategory
        var photos: Int
        var story: String = "A short note about this place."
        var cost: Cost?
        var highlight: String?
    }

    static let timeZoneID = "Asia/Kolkata"

    /// Exactly 100 words (`WordLimit.stopStory`), checked by `WordLimit.count`.
    static let hundredWordStory: String = {
        let words = ("The train pulled in just after dawn and the whole platform seemed to breathe out at once. "
            + "Porters in red shirts shouldered trunks, chai sellers rattled their kettles, and a family of five "
            + "argued cheerfully about which exit led to the taxi rank. I followed the smell of cardamom to a tiny "
            + "stall wedged under the stairs, where an old man poured tea from a great height without spilling a "
            + "drop. We talked about cricket, the monsoon, and his grandson in Pune. When I finally stepped outside, "
            + "the city had fully woken, loud and golden and impossibly alive around me today")
            .split(separator: " ")
        return words.prefix(WordLimit.stopStory).joined(separator: " ")
    }()

    // MARK: Ready-made journeys

    static func oneStop() -> Fixture {
        make([StopSpec(name: "Gateway of India", category: .landmark, photos: 2)])
    }

    /// Mixed photo counts (4, 0, 2, 1), one cost, ends at a Stay (hotel) stop.
    static func fourStops() -> Fixture {
        make([
            StopSpec(name: "Chhatrapati Shivaji Terminus", category: .landmark, photos: 4, story: hundredWordStory),
            StopSpec(name: "Sardar Pav Bhaji", category: .food, photos: 0,
                     cost: Cost(amount: 180, currency: "INR")),
            StopSpec(name: "Siddhivinayak Temple", category: .temple, photos: 2),
            StopSpec(name: "Hotel check-in", category: .stay, photos: 1),
        ])
    }

    /// Eight stops, every photo count 0...4, a Stay stop in the middle, costs in two currencies.
    static func eightStops() -> Fixture {
        make([
            StopSpec(name: "Chhatrapati Shivaji Terminus", category: .landmark, photos: 4, story: hundredWordStory),
            StopSpec(name: "Crawford Market", category: .shopping, photos: 3, cost: Cost(amount: 450, currency: "INR")),
            StopSpec(name: "Sardar Pav Bhaji", category: .food, photos: 2, cost: Cost(amount: 180, currency: "INR")),
            StopSpec(name: "Hotel check-in", category: .stay, photos: 1),
            StopSpec(name: "Siddhivinayak Temple", category: .temple, photos: 0),
            StopSpec(name: "Sanjay Gandhi National Park", category: .nature, photos: 4,
                     cost: Cost(amount: 5, currency: "USD")),
            StopSpec(name: "Bandra Bandstand", category: .landmark, photos: 2),
            StopSpec(name: "Juhu Beach", category: .food, photos: 1, story: hundredWordStory),
        ])
    }

    /// One stop with no photos.
    static func noPhotosStop() -> Fixture {
        make([StopSpec(name: "Marine Drive", category: .nature, photos: 0)])
    }

    /// One stop with four photos (alternating landscape / portrait).
    static func fourPhotosStop() -> Fixture {
        make([StopSpec(name: "Elephanta Caves", category: .landmark, photos: 4)])
    }

    /// One stop whose story is exactly 100 words.
    static func hundredWordStop() -> Fixture {
        make([StopSpec(name: "Chhatrapati Shivaji Terminus", category: .landmark, photos: 1, story: hundredWordStory)])
    }

    /// Landmark, Stay (hotel), food: the hotel is hidden by default privacy.
    static func withStayStop() -> Fixture {
        make([
            StopSpec(name: "Gateway of India", category: .landmark, photos: 1),
            StopSpec(name: "Taj Mahal Palace", category: .stay, photos: 1, cost: Cost(amount: 24000, currency: "INR")),
            StopSpec(name: "Leopold Cafe", category: .food, photos: 1, cost: Cost(amount: 600, currency: "INR")),
        ])
    }

    /// Twelve photo-heavy stops (3 or 4 photos each, every other story 100 words), no Stay stop so default privacy
    /// keeps all twelve. Meant to need more than 20 carousel slides: with cover + map + closing that takes an average
    /// of more than 1.5 slides per stop, which these heavy stops are expected to need (agent F: confirm, and add
    /// stops here if the horizontal composer fits them tighter).
    static func twelveStops() -> Fixture {
        let names = ["Chhatrapati Shivaji Terminus", "Crawford Market", "Mumbadevi Temple", "Zaveri Bazaar",
                     "Kala Ghoda Art Precinct", "Gateway of India", "Colaba Causeway", "Haji Ali Dargah",
                     "Mahalaxmi Dhobi Ghat", "Worli Sea Face", "Bandra Bandstand", "Juhu Beach"]
        let categories: [StopCategory] = [.landmark, .shopping, .temple, .shopping, .landmark, .landmark,
                                          .food, .temple, .landmark, .nature, .landmark, .food]
        return make(names.indices.map { i in
            StopSpec(name: names[i], category: categories[i], photos: 3 + i % 2,
                     story: i % 2 == 0 ? hundredWordStory : "A short note about this place.",
                     highlight: i % 3 == 0 ? "The light at golden hour" : nil)
        })
    }

    /// One stop at the limits of a Story frame: 100-word story, 4 photos, a long place name and a highlight.
    static func storyStressStop() -> Fixture {
        make([StopSpec(name: "Chhatrapati Shivaji Maharaj Vastu Sangrahalaya (Prince of Wales Museum)",
                       category: .landmark, photos: 4, story: hundredWordStory,
                       cost: Cost(amount: 700, currency: "INR"),
                       highlight: "Stood in front of the Ashoka pillar replica for a full ten minutes")])
    }

    // MARK: Builder

    static let modes: [TransportMode] = [.taxi, .walk, .autoRickshaw, .localTrain, .bus, .metro, .ferry]

    /// Journey on 19 Oct 2026 (Asia/Kolkata): stops 90 minutes apart from 08:00, spread north through Mumbai,
    /// every leg with a mode, km and minutes; every other leg has a story.
    static func make(_ specs: [StopSpec], title: String = "A Day in Mumbai", imageData: Bool = true) -> Fixture {
        let container = AppContainer.make(inMemory: true)
        let context = ModelContext(container)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID)!
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!

        let j = Journey(title: title, date: day, city: "Mumbai", country: "India")
        j.timeZoneID = timeZoneID
        j.introNote = "One day, \(specs.count) stops."
        j.closingNote = "Mumbai never sleeps, but I did."
        context.insert(j)
        let editor = JourneyEditor(context: context, photos: NoopPhotoStore())

        var photoSeed = 0
        for (i, spec) in specs.enumerated() {
            let s = Stop(placeName: spec.name, story: spec.story, category: spec.category)
            s.latitude = 18.92 + Double(i) * 0.03
            s.longitude = 72.83 + Double(i % 3) * 0.01
            s.cityHint = "Mumbai"
            s.arrivalTime = cal.date(byAdding: .minute, value: 8 * 60 + i * 90, to: day)
            s.timeSpentMinutes = 30 + (i % 3) * 15
            s.rating = i % 5 + 1
            s.cost = spec.cost
            if let h = spec.highlight { s.highlight = h }
            editor.addStop(s, to: j)
            for p in 0..<spec.photos {
                let photo = StopPhoto(orderIndex: p, isHero: p == 0)
                let portrait = p % 2 == 1
                let size = portrait ? CGSize(width: 1536, height: 2048) : CGSize(width: 2048, height: 1536)
                photo.pixelWidth = Int(size.width)
                photo.pixelHeight = Int(size.height)
                photo.captureDate = s.arrivalTime
                photo.caption = p == 0 ? spec.name : nil
                if imageData { photo.imageData = jpeg(seed: photoSeed, size: size) }
                photoSeed += 1
                s.photos.append(photo)
            }
        }
        for (i, s) in j.orderedStops.enumerated() {
            guard let l = s.outgoingLeg else { continue }
            l.mode = modes[i % modes.count]
            l.distanceKm = 2.5 + Double(i)
            l.durationMinutes = 12 + i * 4
            l.story = i % 2 == 0 ? "Leg \(i + 1): the driver knew a shortcut." : nil
        }
        try? context.save()
        return Fixture(container: container, context: context, journey: j)
    }

    // MARK: Images

    private static var jpegCache: [String: Data] = [:]

    /// Photo-like JPEG (gradient plus seeded blobs, quality 0.85): compresses like a real photo, identical for a seed.
    static func jpeg(seed: Int, size: CGSize = CGSize(width: 2048, height: 1536)) -> Data {
        let key = "\(seed)-\(Int(size.width))x\(Int(size.height))"
        if let hit = jpegCache[key] { return hit }
        var rng = SeededRNG(seed: UInt64(seed) &+ 1)
        let img = ImageDrawing.render(size: size, opaque: true) { c in
            let hue = Double(seed % 7) / 7
            let g = CGGradient(colorsSpace: ImageDrawing.sRGB,
                               colors: [ImageDrawing.color(hue: hue, saturation: 0.5, brightness: 0.9),
                                        ImageDrawing.color(hue: hue + 0.1, saturation: 0.7, brightness: 0.4)] as CFArray,
                               locations: [0, 1])!
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            for _ in 0..<1200 {
                c.setFillColor(ImageDrawing.color(hue: .random(in: 0...1, using: &rng), saturation: 0.6,
                                                  brightness: .random(in: 0.3...1, using: &rng), alpha: 0.5))
                c.fillEllipse(in: CGRect(x: .random(in: 0...size.width, using: &rng),
                                         y: .random(in: 0...size.height, using: &rng),
                                         width: .random(in: 4...60, using: &rng), height: .random(in: 4...60, using: &rng)))
            }
        }!
        let data = ImageDrawing.jpegData(img, quality: 0.85)!
        jpegCache[key] = data
        return data
    }
}

/// SplitMix64: a tiny deterministic generator so fixture images are byte-stable across runs.
nonisolated struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
