import Foundation

/// Deterministic sample stories for previews and tests (pure values; no SwiftData).
enum LibraryFixtures {
    private static let places: [(country: String, cities: [String])] = [
        ("India", ["Mumbai", "Delhi", "Goa", "Jaipur"]),
        ("Japan", ["Tokyo", "Kyoto", "Osaka"]),
        ("France", ["Paris", "Lyon"]),
        ("Italy", ["Rome", "Florence"]),
        ("Portugal", ["Lisbon", "Porto"]),
        ("Brazil", ["São Paulo", "Rio"]),
        ("Switzerland", ["Zürich"]),
    ]
    private static let titles = ["A Day in", "Morning in", "Lost in", "Slow Weekend in", "Night Train to", "Coffee in", "Rain over"]

    private static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    /// `count` stories, newest first by index (index 0 is newest). Countries rotate through the table.
    /// - singleCountry: every story is in India.
    /// - noCountryEvery: every Nth story (1-based) has no country (city may remain).
    static func stories(count: Int, singleCountry: Bool = false, noCountryEvery: Int? = nil) -> [LibraryStory] {
        let newest = Date(timeIntervalSince1970: 1_792_000_000) // fixed: 2026-10-14-ish
        return (0..<count).map { i in
            let p = singleCountry ? places[0] : places[i % places.count]
            let city = p.cities[(i / (singleCountry ? 1 : places.count)) % p.cities.count]
            let date = newest.addingTimeInterval(-Double(i) * 9.5 * 86_400)
            let noCountry = noCountryEvery.map { $0 > 0 && (i + 1) % $0 == 0 } ?? false
            return LibraryStory(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i + 1))!,
                title: "\(titles[i % titles.count]) \(city)",
                date: date, dateText: dateText(date),
                city: city, country: noCountry ? nil : p.country,
                weight: 2 + (i * 7) % 9,
                coverPath: nil)
        }
    }

    /// The scenarios the spec requires previews for.
    static let scenarioCounts = [0, 1, 6, 7, 10, 11, 19, 60]
}
