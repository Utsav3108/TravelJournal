import Foundation
import FoundationModels

struct Prompts: Codable { var instructions, placeName, category, arrival, story, highlight, rating, cost, minutes, travelMode: String }
nonisolated(unsafe) var P = Prompts(instructions:"",placeName:"",category:"",arrival:"",story:"",highlight:"",rating:"",cost:"",minutes:"",travelMode:"")

@Generable
struct VoiceStopDraft: Equatable {
    @Guide(description: "true only if a specific place name was spoken") var hasPlace: Bool
    @Guide(description: P.placeName) var placeName: String
    @Guide(description: "true only if the kind of place is clearly stated or obvious from its name") var hasCategory: Bool
    @Guide(description: P.category) var category: Category
    @Guide(description: "true only if an arrival clock time was spoken") var hasArrival: Bool
    @Guide(description: P.arrival) var arrival: String
    @Guide(description: "true only if the traveller described the visit or experience in words") var hasStory: Bool
    @Guide(description: P.story) var story: String
    @Guide(description: P.highlight) var highlight: String
    @Guide(description: "true only if a star rating or score out of 5 was spoken") var hasRating: Bool
    @Guide(description: P.rating, .range(1...5)) var rating: Int
    @Guide(description: "true only if an amount of money or free was spoken") var hasCost: Bool
    @Guide(description: P.cost, .range(0...10_000_000)) var cost: Double
    @Guide(description: "true only if a duration spent at the place was spoken") var hasMinutes: Bool
    @Guide(description: P.minutes, .range(0...1440)) var minutesSpent: Int
    @Guide(description: "true only if a vehicle or walking was explicitly spoken") var hasTravelMode: Bool
    @Guide(description: P.travelMode) var travelMode: TravelMode
    @Generable enum Category: String, CaseIterable { case food, landmark, temple, stay, shopping, nature, other }
    @Generable enum TravelMode: String, CaseIterable { case walk, autoRickshaw, taxi, bus, localTrain, metro, bike, ferry }
}

struct Case: Codable { var id: Int; var text: String; var holdout: Bool }
struct Out: Codable { var id: Int; var runs: [[String: String]] }

@main struct Main {
  static func main() async {
    let a = CommandLine.arguments
    guard a.count >= 6 else { print("usage: h prompts.json corpus.json out.json subset(train|hold|all) runs"); return }
    guard case .available = SystemLanguageModel.default.availability else { print("UNAVAILABLE \(SystemLanguageModel.default.availability)"); exit(2) }
    P = try! JSONDecoder().decode(Prompts.self, from: Data(contentsOf: URL(fileURLWithPath: a[1])))
    var cases = try! JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: a[2])))
    switch a[4] { case "train": cases = cases.filter{!$0.holdout}; case "hold": cases = cases.filter{$0.holdout}; default: break }
    let runs = Int(a[5])!
    var outs: [Out] = []
    for c in cases {
      var rs: [[String:String]] = []
      for _ in 0..<runs {
        var d: [String:String] = [:]
        do {
          let s = LanguageModelSession(instructions: P.instructions)
          let r = try await s.respond(to: c.text, generating: VoiceStopDraft.self).content
          if r.hasPlace { d["place"] = r.placeName }
          if r.hasCategory { d["category"] = r.category.rawValue }
          if r.hasArrival { d["arrival"] = r.arrival }
          if r.hasStory { d["story"] = r.story; d["highlight"] = r.highlight }
          if r.hasRating { d["rating"] = String(r.rating) }
          if r.hasCost { d["cost"] = String(r.cost) }
          if r.hasMinutes { d["minutes"] = String(r.minutesSpent) }
          if r.hasTravelMode { d["travelMode"] = r.travelMode.rawValue }
        } catch { d["_error"] = "\(error)" }
        rs.append(d)
      }
      outs.append(Out(id: c.id, runs: rs))
      FileHandle.standardError.write("done \(c.id)\n".data(using:.utf8)!)
    }
    try! JSONEncoder().encode(outs).write(to: URL(fileURLWithPath: a[3]))
  }
}
