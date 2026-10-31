import Foundation
import SwiftData
import ImageIO

/// Sample content for previews/tests. Coordinates are approximate (layout/maps only).
enum SampleData {
    @MainActor
    @discardableResult
    static func mumbai(in context: ModelContext) -> Journey {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }

        let j = Journey(title: "A Day in Mumbai", date: day, city: "Mumbai")
        j.timeZoneID = "Asia/Kolkata"
        j.introNote = "One day, four stops, too much butter."
        j.closingNote = "Mumbai never sleeps, but I did."
        context.insert(j)

        let editor = JourneyEditor(context: context, photos: NoopPhotoStore())

        func photos(_ key: String, _ n: Int, _ s: Stop) {
            for i in 0..<n {
                let p = StopPhoto(orderIndex: i, isHero: i == 0)   // no imageData: sample photos draw a placeholder
                p.pixelWidth = i % 2 == 0 ? 1600 : 1200
                p.pixelHeight = i % 2 == 0 ? 1200 : 1600
                p.captureDate = s.arrivalTime
                s.photos.append(p)
            }
        }

        let cst = Stop(placeName: "Chhatrapati Shivaji Terminus",
                       story: "The morning light hits the Gothic arches and the whole station hums. Commuters pour out in waves while pigeons own the rafters. I stood still for a minute and let the city rush around me.",
                       category: .landmark)
        cst.latitude = 18.9398; cst.longitude = 72.8355; cst.cityHint = "Mumbai"
        cst.arrivalTime = at(8, 30); cst.timeSpentMinutes = 30; cst.rating = 4
        editor.addStop(cst, to: j)
        photos("cst", 4, cst)

        let pav = Stop(placeName: "Sardar Pav Bhaji", story: "Butter on butter on butter. Worth the queue.", category: .food)
        pav.latitude = 18.9718; pav.longitude = 72.8115; pav.cityHint = "Mumbai"
        pav.arrivalTime = at(11); pav.timeSpentMinutes = 45; pav.rating = 5
        pav.highlight = "best butter pav of my life"
        pav.cost = Cost(amount: 180, currency: "INR")
        editor.addStop(pav, to: j)
        photos("pav", 3, pav)

        let temple = Stop(placeName: "Siddhivinayak Temple", story: "Marigolds, bells and a slow, patient line.", category: .temple)
        temple.latitude = 19.0169; temple.longitude = 72.8300
        temple.arrivalTime = at(14); temple.timeSpentMinutes = 60
        editor.addStop(temple, to: j)
        photos("temple", 1, temple)

        let hotel = Stop(placeName: "Hotel check-in", story: "Shoes off, fan on.", category: .stay)
        hotel.latitude = 19.0176; hotel.longitude = 72.8562
        hotel.arrivalTime = at(18)
        editor.addStop(hotel, to: j)

        func leg(_ a: Stop, _ mode: TransportMode, _ km: Double, _ min: Int, _ story: String? = nil) {
            guard let l = a.outgoingLeg else { return }
            l.mode = mode; l.distanceKm = km; l.durationMinutes = min; l.story = story
        }
        leg(cst, .taxi, 5.2, 18, "The driver knew a shortcut via Kalbadevi.")
        leg(pav, .taxi, 4, 25)
        leg(temple, .autoRickshaw, 6, 20)
        return j
    }

    /// The journey new users get from "Add sample journey": one day across Manhattan and Brooklyn that shows off real photos,
    /// located stops (so the story map, route and Maps all work) and a different way of getting around on every leg.
    /// Photos are bundled CC0 images (see docs/sample-photo-credits.md).
    @MainActor
    @discardableResult
    static func newYork(in context: ModelContext) -> Journey {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 24))!
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }

        let j = Journey(title: "One Big Day in New York", date: day, city: "New York", country: "United States")
        j.timeZoneID = "America/New_York"
        j.introNote = "Eight stops, six ways to get around, one very tired pair of shoes."
        j.closingNote = "The city never sleeps. For one day, neither did I."
        context.insert(j)

        let editor = JourneyEditor(context: context, photos: NoopPhotoStore())

        func stop(_ name: String, _ story: String, _ category: StopCategory, _ lat: Double, _ lon: Double,
                  arrive: Date, minutes: Int, rating: Int? = nil, highlight: String? = nil, cost: Decimal? = nil,
                  photos: [(String, String)]) -> Stop {
            let s = Stop(placeName: name, story: story, category: category)
            s.latitude = lat; s.longitude = lon; s.cityHint = "New York"
            s.arrivalTime = arrive; s.timeSpentMinutes = minutes; s.rating = rating; s.highlight = highlight
            if let cost { s.cost = Cost(amount: cost, currency: "USD") }
            editor.addStop(s, to: j)
            addBundledPhotos(photos, to: s)
            return s
        }

        let gct = stop("Grand Central Terminal",
                       "Started under the green-blue ceiling, neck bent back like every other tourist. The whole concourse hums with people who know exactly where they are going. I did not, so I just stood in the middle and watched the clock.",
                       .landmark, 40.7527, -73.9772, arrive: at(8), minutes: 40, rating: 5,
                       highlight: "the ceiling is worth the stiff neck",
                       photos: [("nyc-gct-concourse", "Main concourse"), ("nyc-gct-ceiling", "The ceiling")])
        let bridge = stop("Brooklyn Bridge",
                          "Walked the whole bridge, slowly, because the skyline kept pulling my eyes backwards. Cyclists ring their bells at anyone who stops for a photo, which is everyone. Stay on the walking side.",
                          .landmark, 40.7061, -73.9969, arrive: at(9, 30), minutes: 70, rating: 5,
                          highlight: "Manhattan keeps getting smaller behind you",
                          photos: [("nyc-bridge-view", "The skyline from the walkway"), ("nyc-bridge-walk", "Towers ahead"),
                                   ("nyc-bridge-panorama", "Brooklyn side")])
        let slice = stop("A slice in DUMBO",
                         "A foldable slice, eaten standing up, with the Manhattan Bridge framed at the end of the street. Best five dollars of the trip.",
                         .food, 40.7033, -73.9903, arrive: at(11, 30), minutes: 50, rating: 4,
                         highlight: "pizza with a bridge view", cost: 5,
                         photos: [("nyc-dumbo-view", "The famous street view"), ("nyc-pizza", "Lunch")])
        let battery = stop("Battery Park",
                           "Castle Clinton, a fort turned ticket office, with glass towers rising right behind it. Queued for the ferry in the sun and watched the harbour fill with boats.",
                           .nature, 40.7033, -74.0170, arrive: at(13, 30), minutes: 40,
                           photos: [("nyc-battery-castle", "Castle Clinton"), ("nyc-battery-interior", "Inside the fort")])
        let liberty = stop("Statue of Liberty",
                           "Seen from the free Staten Island Ferry, which is the trick: same view, no ticket, no queue for the crown. She is smaller than you expect and somehow more moving for it.",
                           .landmark, 40.6892, -74.0445, arrive: at(14, 30), minutes: 45, rating: 5,
                           highlight: "the free ferry is the best deal in town",
                           photos: [("nyc-liberty-front", "Lady Liberty"), ("nyc-liberty-ferry", "Lower Manhattan behind us"),
                                    ("nyc-liberty-dusk", "A last look")])
        let hudson = stop("Hudson River Park",
                          "Off the bus and onto the waterfront. Joggers, dogs and a very slow afternoon. Good place to rest your feet before the evening.",
                          .nature, 40.7326, -74.0112, arrive: at(16, 45), minutes: 60,
                          photos: [("nyc-hudson-park", "The river path")])
        let times = stop("Times Square",
                         "Loud, bright and completely unreasonable. Walked a full circle with my head tilted up, then bought nothing and loved it anyway.",
                         .shopping, 40.7580, -73.9855, arrive: at(19), minutes: 60, rating: 3,
                         highlight: "sensory overload, in a good way",
                         photos: [("nyc-times-sunset", "Dusk on Broadway"), ("nyc-times-lights", "Billboards after dark")])
        let esb = stop("Empire State Building",
                       "Ended the day looking up at it instead of down from it. The lights come on, the crowd thins and the whole day finally catches up with my feet.",
                       .landmark, 40.7484, -73.9857, arrive: at(21), minutes: 30, rating: 5,
                       highlight: "the best way to end a long day",
                       photos: [("nyc-esb-sunset", "Sunset on the spire"), ("nyc-esb-day", "Looking straight up")])

        func leg(_ a: Stop, _ mode: TransportMode, _ km: Double, _ min: Int, _ story: String? = nil) {
            guard let l = a.outgoingLeg else { return }
            l.mode = mode; l.distanceKm = km; l.durationMinutes = min; l.story = story
        }
        leg(gct, .metro, 5.5, 15, "The 6 train downtown, standing room only.")
        leg(bridge, .walk, 2.0, 35, "Across the bridge on foot, camera out the whole way.")
        leg(slice, .bike, 4.5, 25, "A Citi Bike back over the Brooklyn Bridge.")
        leg(battery, .ferry, 6.0, 25, "The Staten Island Ferry, free and open-air.")
        leg(liberty, .bus, 9.5, 45, "Back on land, the M20 bus up the west side.")
        leg(hudson, .taxi, 4.8, 22, "A yellow cab, because my feet insisted.")
        leg(times, .walk, 1.4, 20)

        j.coverPhotoID = bridge.photos.first(where: \.isHero)?.id
        j.mapStopID = bridge.id
        return j
    }

    /// Attaches bundled JPEGs (first is the hero). A missing file leaves a placeholder photo instead of failing.
    @MainActor
    private static func addBundledPhotos(_ files: [(String, String)], to stop: Stop) {
        for (i, file) in files.enumerated() {
            let p = StopPhoto(orderIndex: i, isHero: i == 0)
            if let url = Bundle.main.url(forResource: file.0, withExtension: "jpg"), let data = try? Data(contentsOf: url) {
                p.imageData = data
                if let src = CGImageSourceCreateWithData(data as CFData, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                    p.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                    p.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                }
            }
            p.caption = file.1
            p.captureDate = stop.arrivalTime
            p.latitude = stop.latitude; p.longitude = stop.longitude
            stop.photos.append(p)
        }
    }

    #if DEBUG
    /// Inserts `count` lightweight journeys (ids match `LibraryFixtures.stories(count:)`); every 9th has no country.
    @MainActor
    static func library(count: Int, in context: ModelContext) {
        for s in LibraryFixtures.stories(count: count, noCountryEvery: 9) {
            let j = Journey(title: s.title, date: s.date, city: s.city, country: s.country)
            j.id = s.id
            j.timeZoneID = "UTC"
            context.insert(j)
        }
        try? context.save()
    }

    /// Reads `-seedLibrary N`; seeds only when the store has no journeys.
    @MainActor
    static func seedFromLaunchArguments(in context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-seedLibrary"), i + 1 < args.count,
              let n = Int(args[i + 1]), n > 0 else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Journey>())) ?? 0
        guard existing == 0 else { return }
        library(count: n, in: context)
    }
    #endif
}
