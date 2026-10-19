// DELETE AT MERGE: minimal stand-ins for B1 (DesignSystem) and B2 (Models) symbols.
import SwiftUI
import SwiftData

enum KraftColor {
    static let paper = Color(red: 0.953, green: 0.922, blue: 0.867)
    static let paperDeep = Color(red: 0.89, green: 0.84, blue: 0.75)
    static let kraft = Color(red: 0.78, green: 0.63, blue: 0.45)
    static let kraftDark = Color(red: 0.55, green: 0.42, blue: 0.28)
    static let ink = Color(red: 0.17, green: 0.13, blue: 0.10)
    static let inkSoft = Color(red: 0.35, green: 0.30, blue: 0.26)
    static let route = Color(red: 0.62, green: 0.25, blue: 0.20)
    static let sealRose = Color(red: 0.70, green: 0.35, blue: 0.38)
    static let stampTeal = Color(red: 0.20, green: 0.45, blue: 0.45)
}
enum KraftFont {
    static func script(_ size: CGFloat) -> Font { .custom("Allura-Regular", size: size) }
}
enum KraftFonts { static func register() {} }

@Model final class Journey {
    var title: String = ""
    var date: Date = Date()
    var city: String?
    var introNote: String?
    var closingNote: String?
    var stops: [Stop] = []
    init(title: String, date: Date = .now, city: String? = nil) {
        self.title = title; self.date = date; self.city = city
    }
}
@Model final class Stop {
    var placeName: String = ""
    init() {}
}
enum AppContainer {
    static func make(inMemory: Bool) -> ModelContainer {
        try! ModelContainer(for: Journey.self, Stop.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }
}
enum SampleData {
    @discardableResult
    static func mumbai(in context: ModelContext) -> Journey {
        let j = Journey(title: "A Day in Mumbai", city: "Mumbai"); context.insert(j); return j
    }
}
