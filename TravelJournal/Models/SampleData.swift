import Foundation
import SwiftData

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
                let p = StopPhoto(relativePath: "sample:\(key)-\(i + 1)", thumbRelativePath: "sample:\(key)-\(i + 1)",
                                  orderIndex: i, isHero: i == 0)
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
}
