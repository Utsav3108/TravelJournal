import Foundation
import FoundationModels

struct Prompts: Codable { var instructions, placeName, category, arrival, story, highlight, rating, cost, minutes, travelMode: String }
nonisolated(unsafe) var P = Prompts(instructions:"",placeName:"",category:"",arrival:"",story:"",highlight:"",rating:"",cost:"",minutes:"",travelMode:"")

@Generable
struct VoiceStopDraft: Equatable {
    @Guide(description: P.placeName) var placeName: String?
    @Guide(description: P.category) var category: Category?
    @Guide(description: P.arrival) var arrival: String?
    @Guide(description: P.story) var story: String?
    @Guide(description: P.highlight) var highlight: String?
    @Guide(description: P.rating, .range(1...5)) var rating: Int?
    @Guide(description: P.cost, .range(0...10_000_000)) var cost: Double?
    @Guide(description: P.minutes, .range(0...1440)) var minutesSpent: Int?
    @Guide(description: P.travelMode) var travelMode: TravelMode?
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
          if let v = r.placeName { d["place"] = v }
          if let v = r.category { d["category"] = v.rawValue }
          if let v = r.arrival { d["arrival"] = v }
          if let v = r.story { d["story"] = v }
          if let v = r.highlight { d["highlight"] = v }
          if let v = r.rating { d["rating"] = String(v) }
          if let v = r.cost { d["cost"] = String(v) }
          if let v = r.minutesSpent { d["minutes"] = String(v) }
          if let v = r.travelMode { d["travelMode"] = v.rawValue }
        } catch { d["_error"] = "\(error)" }
        rs.append(d)
      }
      outs.append(Out(id: c.id, runs: rs))
      FileHandle.standardError.write("done \(c.id)\n".data(using:.utf8)!)
    }
    try! JSONEncoder().encode(outs).write(to: URL(fileURLWithPath: a[3]))
  }
}
