# L1 - Data & Persistence Design (TravelJournal)

Scope: SwiftData models, ordering and leg sync, photo files, word limit, derived values, container/migration/testing.
Decisions applied (PLAN.md): A4 only, Mood and Tip cut, 100 words per stop, single-day trips.

## 0. Environment findings
- `IPHONEOS_DEPLOYMENT_TARGET = 27.0` (all targets), `SWIFT_VERSION = 5.0` (Swift 5 mode, so no strict-concurrency errors for `@Model` use; keep `@MainActor` on UI-facing services anyway).
- Everything below uses only SwiftData APIs that exist since iOS 17/18: `@Model`, `@Attribute(.externalStorage / .preserveValueOnDeletion / originalName:)`, `@Relationship(deleteRule:inverse:)`, `#Index`, `VersionedSchema`, `SchemaMigrationPlan`, `ModelConfiguration(isStoredInMemoryOnly:)`. At target 27.0 no `#available` guards are needed. I did not verify iOS 27 specific additions (no SDK docs offline); none are required.
- Template state: `Item.swift` (`@Model Item{timestamp}`), `TravelJournalApp` builds `Schema([Item.self])` and `fatalError`s on container failure. Both get replaced (Item deleted).

## 1. Models

Rules used everywhere:
- Every stored property has a default or is optional (keeps lightweight migration and a future CloudKit option open; no `@Attribute(.unique)`).
- Enums are stored as `String` raw values with a computed typed accessor that falls back to a safe case for unknown values (a future/removed case never crashes decoding, unlike storing a `Codable` enum directly).
- Coordinates are two optional `Double`s (`CLLocationCoordinate2D` is not Codable). A stop without both lat and lon is excluded from the map.
- Money is `Decimal?` + ISO 4217 code (`"INR"`), never `Double`.
- All identifiers are `UUID` (`id`), stable and used for seeded rotation (spec: rotation/tape seeded by element id).

```swift
import Foundation
import SwiftData

enum StopCategory: String, CaseIterable, Codable {
    case food, landmark, temple, stay, shopping, nature, other
}
enum TransportMode: String, CaseIterable, Codable {
    case walk, autoRickshaw, taxi, bus, localTrain, metro, bike, ferry
}

@Model final class Journey {
    @Attribute(.unique) ... // NOT used. Plain id:
    var id: UUID = UUID()
    var title: String = ""                 // required (UI blocks empty; model default "")
    var date: Date = Date()                // required; stored as startOfDay in `timeZoneID`
    var timeZoneID: String = TimeZone.current.identifier
    var city: String?                      // nil => derived (see 5)
    var coverPhotoID: UUID?                // user/auto override; nil => first stop hero
    var introNote: String?
    var closingNote: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var schemaTag: Int = 1                 // cheap forward-compat marker, optional
    @Relationship(deleteRule: .cascade, inverse: \Stop.journey)
    var stops: [Stop] = []
    init(title: String, date: Date = .now, city: String? = nil) { ... }

    var orderedStops: [Stop] { stops.sorted { $0.orderIndex < $1.orderIndex } }
}

@Model final class Stop {
    var id: UUID = UUID()
    var orderIndex: Int = 0                // 0...n-1, dense (see 2)
    var journey: Journey?
    var placeName: String = ""             // required
    var story: String = ""                 // required in UI; <= 100 words
    var latitude: Double?; var longitude: Double?; var address: String?
    var arrivalTime: Date?
    var timeSpentMinutes: Int?             // "spent 45 min"
    var categoryRaw: String?               // StopCategory.rawValue
    var highlight: String?                 // one short line, cap ~60 chars in UI
    var rating: Int?                       // 1...5, clamped by setter
    var review: String?
    var costAmount: Decimal?; var costCurrency: String?   // both or neither
    @Relationship(deleteRule: .cascade, inverse: \StopPhoto.stop)
    var photos: [StopPhoto] = []           // 0...4, enforced by PhotoStore
    @Relationship(deleteRule: .cascade, inverse: \Leg.fromStop)
    var outgoingLeg: Leg?                  // leg to the NEXT stop (nil for last stop)
    @Relationship(deleteRule: .cascade, inverse: \Leg.toStop)
    var incomingLeg: Leg?                  // leg from the PREVIOUS stop (nil for first)

    var category: StopCategory? {
        get { categoryRaw.flatMap(StopCategory.init(rawValue:)) ?? (categoryRaw == nil ? nil : .other) }
        set { categoryRaw = newValue?.rawValue }
    }
    var coordinate: CLLocationCoordinate2D? { /* both non-nil */ }
    var orderedPhotos: [StopPhoto] { photos.sorted { $0.orderIndex < $1.orderIndex } }
    var hero: StopPhoto? { photos.first(where: \.isHero) ?? orderedPhotos.first }
}

@Model final class StopPhoto {          // one row per file; metadata, not pixels
    var id: UUID = UUID()
    var stop: Stop?
    var orderIndex: Int = 0
    var isHero: Bool = false              // invariant: exactly one true when photos non-empty
    var relativePath: String = ""         // "Photos/<journeyID>/<id>.jpg", see 3
    var thumbRelativePath: String = ""    // "Photos/<journeyID>/thumbs/<id>.jpg"
    var pixelWidth: Int = 0; var pixelHeight: Int = 0   // after downscale, orientation baked in
    var captureDate: Date?                // EXIF/PHAsset creationDate (used for journey date, arrival)
    var latitude: Double?; var longitude: Double?       // EXIF/PHAsset, for grouping and place lookup
    var caption: String?                  // polaroid caption (Caveat), optional
}

@Model final class Leg {
    var id: UUID = UUID()
    var fromStop: Stop?                   // Leg N: stop N ...
    var toStop: Stop?                     // ... to stop N+1
    var modeRaw: String = TransportMode.walk.rawValue   // required; default is a placeholder
    var modeWasChosen: Bool = false       // false until user picks; lets UI nudge, lets sync overwrite default
    var distanceKm: Double?               // user-entered, >= 0
    var durationMinutes: Int?             // user-entered, >= 0
    var story: String?                    // leg pop-up note; same 100-word helper (suggest 60 in UI)
    var mode: TransportMode {
        get { TransportMode(rawValue: modeRaw) ?? .walk }
        set { modeRaw = newValue.rawValue; modeWasChosen = true }
    }
}
```
(Remove the stray `@Attribute(.unique)` comment line when implementing; shown only as a "do not".)

Design notes:
- **Photos as a model, not `[String]`**: need per-photo hero flag, order, pixel size (layout engine picks templates/aspect), capture date/GPS (grouping, journey date). Pixels never live in the store.
- **Relationship graph / delete rules**: Journey -> Stop cascade; Stop -> StopPhoto cascade; Stop -> Leg cascade on both sides (a Leg is meaningless without either end). Deleting a Journey therefore removes all rows, but NOT files (see 3).
- Optional to-one inverses (`Stop.journey`, `Leg.fromStop`) are mandatory for SwiftData; treat nil as "being deleted/detached" and never force-unwrap in views.
- Index (optional, tiny data set): `#Index<Journey>([\.date])` for shelf sort. Shelf query: `@Query(sort: \Journey.date, order: .reverse)`.
- Validation lives in a plain `Validator` (title non-empty, place non-empty, words <= 100, rating 1...5, cost currency present iff amount) rather than in model `didSet` (SwiftData observation + didSet is brittle).
- Leg `mode` default: `.walk` with `modeWasChosen = false`. Spec says mode is Required, so the leg editor shows the mode picker first and the story/PDF renders a neutral "walk" icon until chosen. Alternative (cleaner but riskier): `modeRaw: String?`. Recommend the default+flag approach: non-optional keeps layout code simple.

## 2. Ordering and leg synchronisation

**Explicit `orderIndex: Int` on Stop**, not reliance on array order: SwiftData to-many relationships are unordered sets (array order is not persisted). Indices are kept dense 0..n-1 by `renumber`.

Invariant (checked in tests): for stops s0..s(n-1): leg i exists iff i < n-1, `leg_i.fromStop == s_i`, `leg_i.toStop == s_(i+1)`. Exactly n-1 legs for n >= 1, 0 for n <= 1.

All mutations go through one `@MainActor` type, `JourneyEditor`, so views never touch `orderIndex` or legs directly:

```swift
@MainActor struct JourneyEditor {
    let context: ModelContext
    let photos: PhotoStoring

    func addStop(_ stop: Stop, to j: Journey, at index: Int? = nil) {
        var list = j.orderedStops
        list.insert(stop, at: min(index ?? list.count, list.count))
        stop.journey = j                     // establishes inverse
        apply(list, in: j)
    }
    func moveStops(in j: Journey, from: IndexSet, to: Int) {   // List .onMove
        var list = j.orderedStops; list.move(fromOffsets: from, toOffset: to)
        apply(list, in: j)
    }
    func deleteStop(_ s: Stop, in j: Journey) {
        photos.removeFiles(for: s.photos)    // files first, rows via cascade
        var list = j.orderedStops.filter { $0 !== s }
        s.outgoingLeg.map(context.delete); s.incomingLeg.map(context.delete)
        context.delete(s)
        apply(list, in: j)
    }
    private func apply(_ list: [Stop], in j: Journey) {
        for (i, s) in list.enumerated() where s.orderIndex != i { s.orderIndex = i }
        LegSync.reconcile(stops: list, context: context)
        j.updatedAt = .now
    }
}
```

`LegSync.reconcile` is idempotent and keyed by the (from,to) pair:

```swift
enum LegSync {
    static func reconcile(stops: [Stop], context: ModelContext) {
        // 1. wanted pairs
        let pairs = zip(stops, stops.dropFirst())
        let wanted = Set(pairs.map { PairKey($0.id, $1.id) })
        // 2. drop legs whose pair is no longer consecutive
        for s in stops { if let l = s.outgoingLeg,
              !(l.toStop.map { wanted.contains(PairKey(s.id, $0.id)) } ?? false) { context.delete(l) } }
        // 3. create missing legs
        for (a, b) in pairs where a.outgoingLeg == nil || a.outgoingLeg?.toStop !== b {
            let leg = Leg(); leg.fromStop = a; leg.toStop = b
            context.insert(leg)
        }
        // 4. last stop must have no outgoing leg (covered by 2 since no wanted pair)
    }
}
```
(Implementation note: after `context.delete`, set `a.outgoingLeg = nil` explicitly before re-creating so in-memory inverses do not hold the deleted object; do reconcile after `try context.save()` of the deletes if a stale-relationship issue shows up in tests.)

What happens to user content (the spec-driven policy):
| Operation | Legs kept | Legs lost | New legs |
|---|---|---|---|
| Add stop at end | all | none | 1 new (prev -> new) |
| Insert stop between A and B | none of A->B (pair broken) | A->B | A->X, X->B, both blank |
| Delete middle stop B in A,B,C | none (A->B, B->C both lost) | both | A->C blank |
| Delete first/last stop | all others | the one adjacent leg | none |
| Reorder (move) | legs whose pair is still adjacent in the same direction | others | blanks for new pairs |

Because a leg's story ("the taxi driver who knew a shortcut") is about a specific pair, it is NOT transplanted onto a different pair. Courtesy mitigations (cheap, recommended):
1. Before applying, `LegSync.preview(...)` returns legs that have content (story, km or minutes) about to be dropped; the UI shows a confirmation ("Deleting this stop also removes 2 leg notes").
2. New blank legs after delete/insert copy only `mode` from the dropped leg adjacent on the same side as a suggestion (`modeWasChosen = false`), nothing else.
3. Reversing a pair (A,B -> B,A) loses the leg: direction matters (the route is directional). Accepted.

Undo: wrap each editor action in `context.undoManager` is optional in v1; confirmation dialog is sufficient.

## 3. Photo storage

Pixels live on disk, only a relative path in `StopPhoto`.
- Base: `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)/TravelJournal/` (create dir on first use). Not Documents: Documents is user-visible only if `UIFileSharingEnabled`, and we do not want raw files in Files. Do NOT exclude from backup (photos here are user content; the app has no backend so device backup is the only safety net).
- **Always store relative paths** (`Photos/<journeyID>/<photoID>.jpg`). The absolute container path changes across reinstall/restore/updates; resolve at read time via `PhotoStore.url(for:)`.
- Layout: `Photos/<journeyID>/<photoID>.jpg` (display, max 2400 px long edge) and `Photos/<journeyID>/thumbs/<photoID>.jpg` (max 600 px).
- Why 2400 px: A4 hero photo at ~300 dpi on a polaroid about 6 in wide is ~1800 px; 2400 gives headroom without 12 MP originals (a 12 MP JPEG decoded is ~48 MB RAM; 2400x1800 is ~17 MB, and PDF with ~20 photos stays manageable).

```swift
protocol PhotoStoring {
    func importPhoto(data: Data, into stop: Stop, journeyID: UUID) throws -> StopPhoto  // throws .limitReached
    func removeFiles(for photos: [StopPhoto])
    func removeAllFiles(forJourney id: UUID)
    func url(for relativePath: String) -> URL
    func sweepOrphans(knownPaths: Set<String>)
}

// Downscale + bake orientation with ImageIO (never UIImage.draw, which decodes full size):
let src = CGImageSourceCreateWithData(data as CFData, nil)!
let opts: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,   // applies EXIF orientation => stored pixels upright
    kCGImageSourceThumbnailMaxPixelSize: 2400,
    kCGImageSourceShouldCacheImmediately: true ]
let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)!
// encode with CGImageDestination, UTType.jpeg, quality 0.85; write to tmp then replaceItemAt (atomic)
```
- Read EXIF GPS/date from `CGImageSourceCopyPropertiesAtIndex` (or PHAsset) BEFORE re-encoding; re-encoding drops it, which is fine for privacy (exported PDF/files carry no GPS) while the values are kept in `StopPhoto.latitude/longitude/captureDate`.
- Large PhotosPicker data: load with `loadTransferable(type: Data.self)`; process one at a time on a background task (`Task.detached`/actor), insert model rows on the main actor. HEIC input is converted to JPEG (universally decodable by `ImageRenderer`/PDF).
- **Max 4 per stop**: `PhotoStore.importPhoto` throws `.limitReached` at 4; picker uses `maxSelectionCount = 4 - stop.photos.count`. Auto-grouping that finds >4 photos in a cluster keeps the first 4 by time and offers the rest as an extra stop (policy for L2/B3).
- **Hero**: first imported photo is hero. `setHero(_:)` clears the other flags in one pass. On deleting the hero, promote the first remaining photo. Deleting the last photo leaves zero heroes (valid).
- **Cleanup**: SwiftData cascade does not delete files. Rule: delete files first (they are re-creatable errors, orphans are harmless), then rows. Covers photo delete, stop delete, journey delete (`removeAllFiles(forJourney:)` just removes the journey folder). Safety net: `sweepOrphans` on launch (background, low priority) deletes files under `Photos/` not referenced by any `StopPhoto` (also handles a crash between file write and `save`). Write the file before inserting the row; on failure delete the file.
- Missing file at render time (e.g. sweep bug, partial restore): views show a paper placeholder, never crash.

## 4. 100-word limit helper

Locale-safe by using the system word segmenter, not `split(separator: " ")` (fails for CJK/Thai and counts punctuation tokens).

```swift
enum WordLimit {
    static let stopStory = 100
    static func count(_ text: String) -> Int {
        var n = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { _,_,_,_ in n += 1 }
        return n
    }
    /// Returns text cut right after the `limit`-th word (keeps original spacing/punctuation up to there).
    static func truncated(_ text: String, to limit: Int = stopStory) -> String {
        var n = 0; var end: String.Index?
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { _, r, _, stop in
            n += 1; if n == limit { end = r.upperBound; stop = true } }
        return end.map { String(text[..<$0]) } ?? text
    }
    static func remaining(_ text: String, limit: Int = stopStory) -> Int { limit - count(text) }
}
```
Behaviour: "pav-bhaji" and "don't" are one word each (segmenter), numbers like "180" count as one; emoji do not count. This slightly differs from what Word shows; the same helper is used for UI, validation and tests, so it is self-consistent.
Enforcement (three layers): (1) editor shows live "73 / 100", turns ink->route colour at >= 90, and in `onChange` of the text binding calls `truncated` so typing/pasting cannot exceed 100 (paste of 300 words is cut, with a brief "trimmed to 100 words" notice); (2) `Validator` re-checks on save; (3) layout engine never trusts it: still lays out defensively (a 100-word story fits one note card per PLAN, but longer legacy data should clip with ellipsis rather than overflow). Leg story: same helper, UI suggests a smaller limit (e.g. 40), undecided; Intro/Closing notes: UI caps (e.g. 40 words) via the same helper.

## 5. Defaults and derived values

Pure functions on plain value snapshots so they are testable without SwiftData.

| Value | Rule |
|---|---|
| Journey.date default | `min(captureDate)` over all photos in the journey, converted to start-of-day in the photo's/device timezone; fallback `.now`. Only applied while the user has not edited the date (`dateIsUserSet` flag optional; simplest: apply at journey creation from first imported batch, and offer a "use photo date" button later). Warn (non-blocking) if photos span > 1 calendar day: single-day trips only. |
| Journey.city | stored value if non-empty, else `orderedStops.first?.cityHint`. `cityHint` is not stored: derive from the first stop's reverse-geocode placemark `locality` and persist it into `Journey.city` once (at that moment the user may still edit). Rule: write only if `journey.city == nil`. |
| Cover photo | `coverPhotoID` match in any stop's photos, else `orderedStops.first?.hero`, else first photo of any stop, else nil (cover shows paper + title only). Cover collage of 3 heroes = first 3 stops' heroes (padding with next photos). |
| Postmark text | `"ARRIVED · \(date) · \(city.uppercased())"` built from the above. |
| Arrival time default | stop's earliest photo `captureDate` (editable, nil allowed). |
| Time spent default | `max(captureDate) - min(captureDate)` of the stop's photos in minutes, rounded, if >= 1 and photos >= 2; else nil. (Suggestion only.) |

Stats (`JourneyStats`, struct computed from the ordered stops and legs):
- `stops` = count; `km` = sum of non-nil `distanceKm`; `photos` = sum of `photos.count`.
- `minutes`: the spec shows "5 h 20 min" without defining it. Proposal: `travelMinutes` (sum of leg durations) + `spentMinutes` (sum of `timeSpentMinutes`). Alternative is wall-clock first arrival -> last arrival + its time spent. Keep both computed; the layout picks one (see Open risks).
- `money`: dictionary `[currencyCode: Decimal]`; display one total if a single currency (e.g. "₹1,240") else joined ("₹1,240 + $12"). No FX conversion in v1.
- `modes` = distinct leg modes, in order of first use, only legs where `modeWasChosen` (for "walk, taxi").
- Missing data is skipped, and the stats strip can show "-" for km if no leg has a distance, so totals never claim precision they lack.

## 6. Drafts, offline, versioning, container, previews, tests

**Draft/offline.** There is no separate draft state: SwiftData autosaves, so every journey is a persisted draft on device and works fully offline (only place lookup in L2 needs network). Create a journey row when the user taps "Create" (so it appears in the shelf immediately), not on app exit. Cancelling a brand-new empty journey deletes it. Add `updatedAt`, bumped by `JourneyEditor` and editors, for shelf sorting/"edited 2h ago". Editors bind directly to the model (live preview in the story, no copy-on-edit); for destructive screens (leg editor with many fields) a scratch copy + Save/Cancel is acceptable but not required. Call `try? context.save()` in `scenePhase == .background` to guarantee flush. Export state is not stored (PDF generated on demand, then shared; optionally `lastExportedAt: Date?`).

**Schema versioning.** Ship V1 wrapped in a `VersionedSchema` from day one so later migrations do not need to retrofit:
```swift
enum TJSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Journey.self, Stop.self, StopPhoto.self, Leg.self] }
}
enum TJMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TJSchemaV1.self] }
    static var stages: [MigrationStage] { [] }   // later: .lightweight(fromVersion:toVersion:) / .custom
}
```
Convention: when V2 is needed, copy the V1 model classes into `TJSchemaV1` namespaced types (frozen) and keep current ones top-level (standard SwiftData pattern). Prefer lightweight changes: adding optional/defaulted properties, adding models; use `@Attribute(originalName:)` for renames; data transforms (e.g. splitting a field) via `.custom` stage. Changing an enum: add cases freely (raw strings are safe), never reuse or rename a raw value. Already-shipped decisions that make migration cheap: raw-string enums, relative photo paths, Decimal+code money, no unique constraints. Never delete the store on migration failure (see below).

**ModelContainer (replace template).**
```swift
@main struct TravelJournalApp: App {
    let container: ModelContainer
    init() {
        do { container = try Persistence.makeContainer() }
        catch { /* show a recoverable error screen with "Export data" / "Try again"; do NOT fatalError or wipe */
                container = try! Persistence.makeContainer(inMemory: true); launchError = error }
    }
    var body: some Scene { WindowGroup { RootView() }.modelContainer(container) }
}
enum Persistence {
    static let schema = Schema(versionedSchema: TJSchemaV1.self)
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)   // default store in Application Support
        return try ModelContainer(for: schema, migrationPlan: TJMigrationPlan.self, configurations: [cfg])
    }
}
```
Keep the store default (Application Support/default.store); photos in a sibling `TravelJournal/Photos` folder. Inject `PhotoStoring` via `@Environment` (custom `EnvironmentKey`), real impl in app, a temp-dir impl in tests/previews.

**In-memory sample data (Mumbai).** `SampleData.insertMumbai(into: ModelContext)` builds Journey "A Day in Mumbai" (date fixed, e.g. 2026-10-19, city "Mumbai", intro/closing notes) and uses `JourneyEditor.addStop` so previews exercise the real sync code:
1. Chhatrapati Shivaji Terminus - landmark - 18.9398, 72.8355 - arrival 08:30 - spent 30 min - rating 4 - story ~60 words.
2. Sardar Pav Bhaji (Tardeo) - food - ~18.9718, 72.8115 - 11:00 - 45 min - cost 180 INR - highlight "best butter pav of my life" - rating 5.
3. Siddhivinayak Temple (Prabhadevi) - temple - ~19.0169, 72.8300 - 14:00 - 60 min - no cost.
4. Hotel check-in - stay - ~19.0176, 72.8562 (approximate, adjust) - 18:00 - nil.
Legs: 1->2 taxi 5.2 km 18 min story "driver knew a shortcut via Kalbadevi"; 2->3 local train... use taxi 4 km 25 min; 3->4 auto-rickshaw 6 km 20 min. Coordinates are approximate and only for layout/maps, state that in the file comment.
Photos: sample `StopPhoto` rows use `relativePath = "sample:cst-1"` etc.; `PhotoStore.url/image(for:)` resolves the `sample:` prefix to asset-catalog images, so previews need no disk and `0...4` photo counts per stop can be demonstrated (give stops 0, 1, 3, 4 photos). Also export fixtures `SampleData.emptyJourney`, `.fourPhotoStop` for the template galleries. Preview helper: `ModelContainer.preview` (in-memory) with `@MainActor static let`.

**Testability.**
- Pure logic (WordLimit, LegSync.preview/invariants, JourneyStats, derived defaults) has no UI deps; XCTest/Swift Testing with `Persistence.makeContainer(inMemory: true)` and a `ModelContext(container)`.
- `PhotoStoring` protocol + `TempDirPhotoStore` (UUID temp folder removed in `tearDown`).
- Suggested tests: invariant holds after random sequences of add/insert/move/delete (property-style, seeded); delete middle stop yields exactly one blank leg; legs with content survive an unrelated move; 5th photo throws; hero promoted on delete; journey delete removes folder; orphan sweep removes only unreferenced files; word count for "pav-bhaji", Devanagari/Hindi text, and 100/101-word boundaries; unknown `categoryRaw` decodes to `.other`; stats with nil km; multi-currency money.

## Open risks
1. **Relationship staleness in `LegSync`**: SwiftData inverse updates after `context.delete` can lag within a transaction. Mitigation: explicit nil-ing plus an invariant test in the first build phase; fall back to `save()` between delete and create.
2. **Two cascade relationships to the same `Leg`** (`outgoingLeg` and `incomingLeg`) is legal but unusual; if SwiftData misbehaves, switch to a single owned side (`outgoingLeg` cascade, `incomingLeg` nullify) and delete via sync.
3. **"Minutes" in stats is undefined by the spec** (travel vs. whole day). Needs a one-line product decision before the closing page ships.
4. **Mode "required" vs. default**: shipping `walk` + `modeWasChosen=false` can show a mode the user never picked in the PDF. Decide whether export is blocked or the icon is shown neutral until chosen.
5. **Leg content loss on reorder/insert** is by design but could surprise users; confirmation prompt is specified, but no undo in v1.
6. **Timezones**: `Journey.date` stored as start-of-day with `timeZoneID`; photos taken abroad or travel-day boundaries may shift the date by one. Edge cases not handled.
7. **Word counting parity** with user expectations (hyphens, numbers); also 100 words in non-space languages is a very different amount of text on the page.
8. **iOS 27 target is above what I could verify offline**; if an API signature changed (e.g. `Schema(versionedSchema:)`), the sketches need minor compile fixes. Swift 5 mode is set, so actor-isolation of `ModelContext` use is not compiler-enforced; keep all context use on the main actor (or a dedicated `@ModelActor`) by convention.
9. **Photo memory/time** when importing a 4-photo batch of 12 MP HEIC: must be sequential and off the main thread; large Live Photos/ProRAW are untested.
10. **Backup/size**: photos are backed up with the device; heavy users may grow GBs. No eviction policy in v1.
