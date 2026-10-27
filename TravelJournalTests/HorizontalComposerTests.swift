import XCTest
import SwiftUI
import SwiftData
@testable import TravelJournal

/// Test journeys for the carousel suites.
@MainActor
enum CarouselFixtures {
    /// `count` photo-heavy stops (3 or 4 photos, every other story 100 words, a highlight on every third): the fixture
    /// for journeys that need more than 20 slides.
    static func heavyStops(_ count: Int) -> JourneyFixtures.Fixture {
        let names = ["Chhatrapati Shivaji Terminus", "Crawford Market", "Mumbadevi Temple", "Zaveri Bazaar",
                     "Kala Ghoda Art Precinct", "Gateway of India", "Colaba Causeway", "Haji Ali Dargah",
                     "Mahalaxmi Dhobi Ghat", "Worli Sea Face", "Bandra Bandstand", "Juhu Beach",
                     "Elephanta Caves", "Marine Drive", "Sanjay Gandhi National Park", "Siddhivinayak Temple"]
        let categories: [StopCategory] = [.landmark, .shopping, .temple, .shopping, .landmark, .landmark, .food, .temple,
                                          .landmark, .nature, .landmark, .food, .landmark, .nature, .nature, .temple]
        return JourneyFixtures.make((0..<count).map { i in
            JourneyFixtures.StopSpec(name: names[i % names.count], category: categories[i % categories.count], photos: 3 + i % 2,
                                     story: i % 2 == 0 ? JourneyFixtures.hundredWordStory : "A short note about this place.",
                                     highlight: i % 3 == 0 ? "The light at golden hour" : nil)
        })
    }

    /// Fixture id -> stable ids, since rotations, tape and wobble are seeded from ids (see `VerticalComposerTests`).
    static func stabilized(_ s: JourneySnapshot) -> (JourneySnapshot, [String: String]) {
        func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
        var out = s
        var photoMap: [UUID: UUID] = [:]
        var stopMap: [UUID: UUID] = [:]
        out.id = uuid(1)
        for i in out.stops.indices {
            stopMap[out.stops[i].id] = uuid(1000 + i)
            out.stops[i].id = uuid(1000 + i)
            for k in out.stops[i].photos.indices {
                let stable = uuid(2000 + photoMap.count)
                photoMap[out.stops[i].photos[k].id] = stable
                out.stops[i].photos[k].id = stable
            }
        }
        for i in out.legs.indices {
            out.legs[i].id = uuid(3000 + i)
            out.legs[i].fromStopID = stopMap[out.legs[i].fromStopID] ?? out.legs[i].fromStopID
            out.legs[i].toStopID = stopMap[out.legs[i].toStopID] ?? out.legs[i].toStopID
        }
        out.coverPhotoID = out.coverPhotoID.flatMap { photoMap[$0] }
        var back: [String: String] = [:]
        for (orig, stable) in photoMap { back[stable.uuidString] = orig.uuidString }
        return (out, back)
    }

    /// Looks photos up by their stored id.
    struct RemappedProvider: StoryImageProvider {
        var base: StoryImageProvider
        var ids: [String: String]
        func image(for photo: StoryPhoto, preferThumbnail: Bool, maxPixel: Int) -> CGImage? {
            base.image(for: StoryPhoto(id: ids[photo.id] ?? photo.id, isHero: photo.isHero),
                       preferThumbnail: preferThumbnail, maxPixel: maxPixel)
        }
    }
}

/// `HorizontalComposer` (Instagram carousel): seamless route across slide edges, unsplit blocks, cover inside the grid
/// crop, slice order, privacy, fixed layout and slide counts.
@MainActor
final class HorizontalComposerTests: XCTestCase {
    let spec = OutputSpec.carousel

    private func compose(_ s: JourneySnapshot) -> ComposedDocument { HorizontalComposer().compose(s, spec: spec) }

    private func compose(_ f: JourneyFixtures.Fixture) -> (JourneySnapshot, ComposedDocument) {
        let s = f.snapshot
        return (s, compose(s))
    }

    private var fixtures: [(String, () -> JourneyFixtures.Fixture)] {
        [("oneStop", JourneyFixtures.oneStop), ("fourStops", JourneyFixtures.fourStops),
         ("eightStops", JourneyFixtures.eightStops), ("twelveStops", JourneyFixtures.twelveStops),
         ("noPhotos", JourneyFixtures.noPhotosStop), ("fourPhotos", JourneyFixtures.fourPhotosStop),
         ("hundredWord", JourneyFixtures.hundredWordStop)]
    }

    private func stopSlices(_ d: ComposedDocument) -> [ComposedSlice] { SliceChecks.stopSlices(d) }

    // MARK: Route

    func testSeamsShareTheCutPoint() {
        for (name, make) in fixtures {
            let slides = stopSlices(compose(make()).1)
            XCTAssertNil(slides.first?.routeEntry, "\(name): route starts on the first stop slide")
            XCTAssertNil(slides.last?.routeExit, "\(name): route ends on the last stop slide")
            for k in 0..<max(slides.count - 1, 0) {
                let a = slides[k], b = slides[k + 1]
                guard let exit = a.routeExit, let entry = b.routeEntry else {
                    XCTFail("\(name) seam \(k): missing exit/entry"); continue
                }
                XCTAssertEqual(exit.x, a.size.width, accuracy: 1, "\(name) seam \(k): exit on the trailing edge")
                XCTAssertEqual(entry.x, 0, accuracy: 1, "\(name) seam \(k): entry on the leading edge")
                XCTAssertEqual(exit.y, entry.y, accuracy: 1, "\(name) seam \(k): same y")
                // The drawn route really reaches the edges at those points.
                let lastPt = a.route.last?.points.last, firstPt = b.route.first?.points.first
                XCTAssertEqual(lastPt?.x ?? -1, exit.x, accuracy: 1, "\(name) seam \(k): drawn exit")
                XCTAssertEqual(lastPt?.y ?? -1, exit.y, accuracy: 1)
                XCTAssertEqual(firstPt?.x ?? -1, entry.x, accuracy: 1, "\(name) seam \(k): drawn entry")
                XCTAssertEqual(firstPt?.y ?? -1, entry.y, accuracy: 1)
            }
        }
    }

    func testRouteRunsFromFirstStopToTheEndMarker() {
        for (name, make) in fixtures {
            let (s, doc) = compose(make())
            let slides = stopSlices(doc)
            let firstBlock = slides.first?.blocks.first { if case .stop(0, _) = $0.content { true } else { false } }
            let start = slides.first?.route.first?.points.first
            XCTAssertNotNil(firstBlock?.routeAnchor, name)
            XCTAssertEqual(start?.x ?? -1, firstBlock?.routeAnchor?.x ?? -2, accuracy: 0.5, "\(name): starts at stop 1's pin")
            XCTAssertEqual(start?.y ?? -1, firstBlock?.routeAnchor?.y ?? -2, accuracy: 0.5)

            let end = slides.last?.blocks.first { $0.content == .endMarker }
            XCTAssertNotNil(end, "\(name): end marker on the last stop slide")
            XCTAssertEqual(slides.flatMap(\.blocks).filter { $0.content == .endMarker }.count, 1, name)
            let finish = slides.last?.route.last
            XCTAssertNil(finish?.legIndex, "\(name): last run is the lead-out")
            XCTAssertEqual(finish?.points.last?.x ?? -1, end?.routeAnchor?.x ?? -2, accuracy: 0.5, "\(name): ends at the marker")
            XCTAssertEqual(finish?.points.last?.y ?? -1, end?.routeAnchor?.y ?? -2, accuracy: 0.5)

            // Every stop pin lies on the route.
            for slide in slides {
                let pts = slide.route.flatMap(\.points)
                for b in slide.blocks {
                    guard case .stop = b.content, let a = b.routeAnchor else { continue }
                    XCTAssertTrue(pts.contains { hypot($0.x - a.x, $0.y - a.y) < 0.5 }, "\(name): route visits \(b.id)")
                }
            }

            // One connector per leg, on the first slide of the stop it leads to, with its badge on the route lane.
            let connectors = slides.flatMap(\.connectors)
            XCTAssertEqual(connectors.map(\.legIndex).sorted(), Array(s.legs.indices), name)
            for slide in slides {
                for c in slide.connectors {
                    let leg = s.legs[c.legIndex]
                    XCTAssertNotNil(c.labelFrame, "\(name) leg \(c.legIndex) label")
                    XCTAssertEqual(c.storyFrame != nil, leg.story != nil, "\(name) leg \(c.legIndex) story")
                    let onRoute = slide.route.contains { seg in
                        seg.points.indices.dropLast().contains { k in
                            let a = seg.points[k], b = seg.points[k + 1]
                            return a.x <= c.center.x && c.center.x <= b.x && abs(a.y - c.center.y) < 0.5 && abs(b.y - c.center.y) < 0.5
                        }
                    }
                    XCTAssertTrue(onRoute, "\(name) leg \(c.legIndex): badge sits on the lane")
                    XCTAssertEqual(slide.blocks.first.flatMap { b -> Int? in
                        if case .stop(let i, _) = b.content { i } else { nil } }, c.legIndex + 1, "\(name): leg leads into this slide's stop")
                }
            }
        }
    }

    func testRouteIsOneContinuousPolylineAcrossTheCanvas() {
        for (name, make) in fixtures {
            let doc = compose(make()).1
            let slides = stopSlices(doc)
            // Rebuild canvas coordinates and check the points never go backwards and never jump.
            var last: CGPoint?
            for slide in slides {
                let x0 = CGFloat(slide.index) * slide.size.width
                for seg in slide.route {
                    for p in seg.points {
                        let c = CGPoint(x: p.x + x0, y: p.y)
                        if let l = last {
                            XCTAssertGreaterThanOrEqual(c.x, l.x - 0.01, "\(name): route only moves right")
                            XCTAssertLessThan(hypot(c.x - l.x, c.y - l.y), 560, "\(name): no jump at slide \(slide.index)")
                        }
                        last = c
                    }
                }
            }
        }
    }

    // MARK: Packing

    func testNoBlockCrossesASliceEdge() {
        for (name, make) in fixtures {
            let doc = compose(make()).1
            assertNoSliceEdgeCrossings(doc, axis: .horizontal, name)
            for slide in stopSlices(doc) {
                for b in slide.blocks {
                    XCTAssertGreaterThanOrEqual(b.frame.minX, spec.margins.left - 0.5, "\(name) \(b.id) left margin")
                    XCTAssertLessThanOrEqual(b.frame.maxX, slide.size.width - spec.margins.right + 0.5, "\(name) \(b.id) right margin")
                    XCTAssertGreaterThanOrEqual(b.frame.minY, 0, "\(name) \(b.id)")
                    XCTAssertLessThanOrEqual(b.frame.maxY, slide.size.height, "\(name) \(b.id)")
                }
            }
        }
    }

    func testEveryStopIsPlacedInOrderOnOneOrTwoSlides() {
        for (name, make) in fixtures {
            let (s, doc) = compose(make())
            let slides = stopSlices(doc)
            let order = slides.flatMap(\.blocks).compactMap { b -> Int? in
                if case .stop(let i, _) = b.content { i } else { nil }
            }
            var perStop: [Int: Int] = [:]
            for i in order { perStop[i, default: 0] += 1 }
            XCTAssertEqual(Set(perStop.keys), Set(s.stops.indices), name)
            XCTAssertTrue(perStop.values.allSatisfy { (1...2).contains($0) }, "\(name): a panel is 1 or 2 slides")
            XCTAssertEqual(order, order.sorted(), "\(name): stops in route order")
            // A panel's slides are adjacent, and only the first carries the pin.
            for slide in slides {
                let stops = slide.blocks.filter { if case .stop = $0.content { true } else { false } }
                XCTAssertEqual(stops.count, 1, "\(name) \(slide.id): one stop per slide")
            }
        }
    }

    func testFirstSlideOfAPanelHoldsHeroAndTicket() {
        // A stop with a long story and four photos needs two slides: photos + ticket first, the note card second.
        let f = CarouselFixtures.heavyStops(2)
        let (s, doc) = compose(f)
        let slides = stopSlices(doc)
        let stop0 = slides.filter { $0.blocks.contains { if case .stop(0, _) = $0.content { true } else { false } } }
        XCTAssertEqual(stop0.count, 2, "hundred-word story with 3 photos splits across two slides")
        let panel = StopPanelLayout.make(s.stopPageModel(0), legIn: nil, isLast: false)
        XCTAssertEqual(panel.slideCount, 2)
        XCTAssertNotNil(panel.parts[0].layout.hero)
        XCTAssertFalse(panel.parts[0].layout.ticket.isEmpty)
        XCTAssertTrue(panel.parts[0].layout.card.isEmpty)
        XCTAssertFalse(panel.parts[1].layout.card.isEmpty)
        XCTAssertTrue(panel.parts[1].layout.ticket.isEmpty)
    }

    // MARK: Cover

    func testCoverTitleAndHeroStayInsideTheGridCrop() throws {
        let crop = try XCTUnwrap(spec.gridCropRect)
        for (name, make) in fixtures {
            let (s, doc) = compose(make())
            let cover = try XCTUnwrap(doc.slices.first)
            XCTAssertEqual(cover.kind, .cover)
            for b in cover.blocks { XCTAssertTrue(crop.contains(b.frame), "\(name) cover block \(b.frame) inside \(crop)") }
            let L = CoverLayout.make(s.coverModel, metrics: spec.pageMetrics)
            XCTAssertTrue(crop.contains(L.title), "\(name): title \(L.title) inside the grid crop")
            if let hero = L.hero { XCTAssertTrue(crop.contains(hero), "\(name): hero \(hero) inside the grid crop") }
            for t in L.taped { XCTAssertTrue(crop.contains(t), "\(name): taped photo inside the grid crop") }
        }
    }

    // MARK: Order, privacy, fixed layout

    func testSliceOrder() {
        let doc = compose(JourneyFixtures.fourStops()).1
        let kinds = doc.slices.map(\.kind)
        XCTAssertEqual(kinds.first, .cover)
        XCTAssertEqual(kinds[1], .map)
        XCTAssertEqual(kinds.last, .closing)
        XCTAssertEqual(kinds.filter { $0 == .stops }.count, kinds.count - 3)
        XCTAssertEqual(Array(kinds.dropFirst(2).dropLast()), Array(repeating: .stops, count: kinds.count - 3))
        XCTAssertEqual(doc.slices.map(\.index), Array(doc.slices.indices))
        XCTAssertTrue(doc.slices.allSatisfy { $0.size == spec.sliceSize })
    }

    func testMapSliceIsOmittedWhenTheMapIsHidden() {
        var s = JourneyFixtures.fourStops().snapshot
        let shown = compose(s).slices.count
        s.mapMode = .hidden
        let doc = compose(s)
        XCTAssertFalse(doc.slices.contains { $0.kind == .map })
        XCTAssertEqual(doc.slices.map(\.kind).first, .cover)
        XCTAssertEqual(doc.slices.count, shown - 1)
        // The route keeps its seams: stop slides simply move one place left.
        let slides = stopSlices(doc)
        for k in 0..<(slides.count - 1) {
            XCTAssertEqual(slides[k].routeExit?.y ?? -1, slides[k + 1].routeEntry?.y ?? -2, accuracy: 1)
        }
    }

    func testComposeIsDeterministic() {
        for (name, make) in fixtures {
            let s = make().snapshot
            XCTAssertEqual(compose(s), compose(s), name)
        }
    }

    func testHiddenStayStopLeavesNoTrace() {
        let f = JourneyFixtures.withStayStop()
        let hotel = f.stops[1]
        let options = ExportOptions(format: .carousel, privacy: ExportPrivacy())          // hides Stay stops by default
        let s = options.apply(to: f.snapshot)
        XCTAssertEqual(s.stops.count, 2)
        let doc = compose(s)
        let ids = doc.slices.flatMap(\.blocks).map(\.id)
        XCTAssertFalse(ids.contains { $0.contains(hotel.id.uuidString) }, "no block for the hidden hotel")
        XCTAssertFalse(s.stops.contains { $0.placeName == "Taj Mahal Palace" })
        XCTAssertFalse(s.overviewModel.stops.contains { $0.name == "Taj Mahal Palace" }, "not on the map")
        XCTAssertEqual(s.totals.stops, 2)
        XCTAssertTrue(s.totals.spent.allSatisfy { $0.amount != 24000 }, "not in the totals")
        XCTAssertEqual(s.legs.count, 1)
        XCTAssertEqual(stopSlices(doc).flatMap(\.connectors).map(\.legIndex), [0], "legs merged around the hidden stop")
        let withHotel = compose(ExportOptions(format: .carousel, privacy: ExportPrivacy(hideStayStops: false)).apply(to: f.snapshot))
        XCTAssertGreaterThan(withHotel.slices.count, doc.slices.count - 1)
    }

    /// The layout is fixed: a stop's slides don't depend on how many slides the journey has.
    func testLayoutDoesNotDependOnTheSlideCount() {
        let big = CarouselFixtures.heavyStops(16).snapshot
        let doc = compose(big)
        for i in [0, 5, 9] {
            let alone = StopPanelLayout.make(big.stopPageModel(i, sealIndex: big.sealStopIndex),
                                             legIn: i > 0 ? big.storyLeg(i - 1) : nil, isLast: false)
            let slidesOf = stopSlices(doc).filter { $0.blocks.contains { if case .stop(i, _) = $0.content { true } else { false } } }
            XCTAssertEqual(slidesOf.count, alone.slideCount, "stop \(i)")
            XCTAssertEqual(slidesOf.first?.blocks.first?.frame, alone.parts[0].frame)
        }
    }

    // MARK: Slide counts

    func testSlideCounts() {
        var counts: [String: Int] = [:]
        for (name, make) in fixtures {
            let s = make().snapshot
            let n = HorizontalComposer.slideCount(for: s)
            counts[name] = n
            XCTAssertEqual(n, compose(s).slices.count, name)
            print("CAROUSEL_SLIDES \(name) stops=\(s.stops.count) slides=\(n)")
        }
        XCTAssertLessThanOrEqual(counts["oneStop"] ?? 99, 6)
        XCTAssertLessThanOrEqual(counts["fourStops"] ?? 99, spec.maxSlices ?? 20)
    }

    func testHeavyJourneyGoesOverTwentySlides() {
        let s = CarouselFixtures.heavyStops(16).snapshot
        let n = HorizontalComposer.slideCount(for: s)
        print("CAROUSEL_SLIDES heavy16 stops=16 slides=\(n)")
        XCTAssertGreaterThan(n, spec.maxSlices ?? 20)
        // Dropping stops brings it back under (the over-20 stop picker).
        let keep = Set(s.stops.prefix(8).map(\.id))
        XCTAssertLessThan(HorizontalComposer.slideCount(for: s.including(stopIDs: keep)), n)
    }

    func testRouteOffsetsAccumulateAlongTheRoute() {
        let doc = compose(JourneyFixtures.fourStops())
        let offsets = HorizontalComposer.routeOffsets(doc.1)
        XCTAssertEqual(offsets.count, doc.1.slices.count)
        XCTAssertEqual(offsets.first, 0)
        XCTAssertEqual(offsets, offsets.sorted())
        let first = doc.1.slices.firstIndex { $0.kind == .stops }!
        let len = doc.1.slices[first].route.reduce(0) { $0 + PageRouteGeometry.polylineLength($1.points) }
        XCTAssertEqual(offsets[first + 1], offsets[first] + len, accuracy: 0.001)
    }

    // MARK: Snapshots

    /// Reference snapshots (iOS) of composed slides at 540 x 675 pt. Left to right: cover, map (skipped), stop slides, closing.
    func testComposedSlideSnapshots() throws {
        #if os(macOS)
        var missingMacReferences: [String] = []
        #endif
        let sets: [(String, JourneyFixtures.Fixture)] = [("fourStops", JourneyFixtures.fourStops()),
                                                          ("heavy3", CarouselFixtures.heavyStops(3))]
        for (name, f) in sets {
            let (s, ids) = CarouselFixtures.stabilized(f.snapshot)
            let doc = compose(s)
            let offsets = HorizontalComposer.routeOffsets(doc)
            let provider = CarouselFixtures.RemappedProvider(base: ModelStoryImageProvider(source: ModelPhotoSource(context: f.context)),
                                                             ids: ids)
            for slice in doc.slices where slice.kind != .map {
                if name != "fourStops", slice.kind != .stops { continue }
                let view = CarouselSliceView(slice: slice, snapshot: s, spec: spec, routeOffset: offsets[slice.index],
                                             showsBrandStamp: true)
                    .environment(\.storyImageProvider, provider)
                let img = try XCTUnwrap(TestImages.render(view, proposed: ProposedViewSize(slice.size)), "\(name) \(slice.id)")
                XCTAssertEqual(img.width, Int(slice.size.width))
                XCTAssertEqual(img.height, Int(slice.size.height))
                let snapName = "carousel-\(name)-\(slice.id)"
                #if os(macOS)
                // The sandboxed macOS test host cannot write into the source tree: keep a copy in its temporary directory.
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("carousel-snapshots", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                TestImages.writePNG(img, to: dir.appendingPathComponent("\(snapName)-macos.png"))
                if !FileManager.default.fileExists(atPath: Snapshots.referenceURL(named: snapName).path) {
                    missingMacReferences.append(snapName)
                    continue
                }
                #endif
                assertSnapshot(img, named: snapName, tolerance: 0.002)
            }
        }
        #if os(macOS)
        if !missingMacReferences.isEmpty {
            throw XCTSkip("No macOS references yet for \(missingMacReferences.count) carousel slides; copy them from "
                          + "the test host's tmp/carousel-snapshots into __Snapshots__.")
        }
        #endif
    }
}
