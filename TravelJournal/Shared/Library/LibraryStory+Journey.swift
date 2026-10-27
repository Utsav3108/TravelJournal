import Foundation

extension LibraryStory {
    init(_ j: Journey) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        f.timeZone = TimeZone(identifier: j.timeZoneID) ?? .current
        let cover = j.coverPhoto.flatMap { $0.imageData == nil ? nil : $0.id }
        self.init(id: j.id, title: j.title, date: j.date, dateText: f.string(from: j.date),
                  city: j.displayCity, country: j.displayCountry,
                  weight: max(1, j.stops.count), coverPhotoID: cover, searchText: Self.searchText(for: j))
    }

    /// Stop names and the text the user wrote, so search can match more than the cover.
    static func searchText(for j: Journey) -> String {
        var parts: [String] = []
        if let intro = j.introNote { parts.append(intro) }
        for stop in j.orderedStops {
            parts.append(stop.placeName)
            parts.append(stop.story)
            if let h = stop.highlight { parts.append(h) }
            if let r = stop.review { parts.append(r) }
        }
        if let closing = j.closingNote { parts.append(closing) }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

extension Sequence where Element == Journey {
    var libraryStories: [LibraryStory] { map { LibraryStory($0) } }
}
