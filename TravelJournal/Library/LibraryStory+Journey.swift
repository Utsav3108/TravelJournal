import Foundation

extension LibraryStory {
    init(_ j: Journey) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        f.timeZone = TimeZone(identifier: j.timeZoneID) ?? .current
        var cover = j.coverThumbPath ?? j.coverPhotoPath
        if let c = cover, c.hasPrefix("sample:") { cover = nil }
        self.init(id: j.id, title: j.title, date: j.date, dateText: f.string(from: j.date),
                  city: j.displayCity, country: j.displayCountry,
                  weight: max(1, j.stops.count), coverPath: cover)
    }
}

extension Sequence where Element == Journey {
    var libraryStories: [LibraryStory] { map { LibraryStory($0) } }
}
