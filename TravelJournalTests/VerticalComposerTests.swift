import XCTest
import SwiftUI
import SwiftData
import PDFKit
@testable import TravelJournal

/// `VerticalComposer` (A4 PDF): continuous route across page seams, unsplit blocks, page fill, slice order,
/// plus reference snapshots of the composed pages and the exported PDF size.
@MainActor
final class VerticalComposerTests: XCTestCase {
    let spec = OutputSpec.a4PDF

    private func compose(_ f: JourneyFixtures.Fixture) -> (JourneySnapshot, ComposedDocument) {
        let s = f.snapshot
        return (s, VerticalComposer().compose(s, spec: spec))
    }

    private var fixtures: [(String, () -> JourneyFixtures.Fixture)] {
        [("oneStop", JourneyFixtures.oneStop), ("fourStops", JourneyFixtures.fourStops),
         ("eightStops", JourneyFixtures.eightStops), ("noPhotos", JourneyFixtures.noPhotosStop),
         ("fourPhotos", JourneyFixtures.fourPhotosStop), ("hundredWord", JourneyFixtures.hundredWordStop)]
    }

    private func stopSlices(_ d: ComposedDocument) -> [ComposedSlice] { d.slices.filter { $0.kind == .stops } }

    // MARK: Route

    func testSeamsShareTheCutPoint() {
        for (name, make) in fixtures {
            let pages = stopSlices(compose(make()).1)
            XCTAssertNil(pages.first?.routeEntry, "\(name): route starts on the first stop page")
            XCTAssertNil(pages.last?.routeExit, "\(name): route ends on the last stop page")
            for k in 0..<max(pages.count - 1, 0) {
                let a = pages[k], b = pages[k + 1]
                guard let exit = a.routeExit, let entry = b.routeEntry else {
                    XCTFail("\(name) seam \(k): missing exit/entry"); continue
                }
                XCTAssertEqual(exit.x, entry.x, accuracy: 1, "\(name) seam \(k): same x")
                XCTAssertEqual(exit.y, a.size.height, accuracy: 1, "\(name) seam \(k): exit on the bottom edge")
                XCTAssertEqual(entry.y, 0, accuracy: 1, "\(name) seam \(k): entry on the top edge")
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
            let pages = stopSlices(doc)
            let firstBlock = pages.first?.blocks.first { if case .stop(0, _) = $0.content { true } else { false } }
            let start = pages.first?.route.first?.points.first
            XCTAssertNotNil(firstBlock?.routeAnchor, name)
            XCTAssertEqual(start?.x ?? -1, firstBlock?.routeAnchor?.x ?? -2, accuracy: 0.5, "\(name): starts at stop 1's pin")
            XCTAssertEqual(start?.y ?? -1, firstBlock?.routeAnchor?.y ?? -2, accuracy: 0.5)

            let end = pages.last?.blocks.first { $0.content == .endMarker }
            XCTAssertNotNil(end, "\(name): end marker on the last stop page")
            let finish = pages.last?.route.last
            XCTAssertNil(finish?.legIndex, "\(name): last run is the lead-out")
            XCTAssertEqual(finish?.points.last?.x ?? -1, end?.routeAnchor?.x ?? -2, accuracy: 0.5, "\(name): ends at the marker")
            XCTAssertEqual(finish?.points.last?.y ?? -1, end?.routeAnchor?.y ?? -2, accuracy: 0.5)

            // Every stop pin lies on the route.
            for page in pages {
                let pts = page.route.flatMap(\.points)
                for b in page.blocks {
                    guard case .stop = b.content, let a = b.routeAnchor else { continue }
                    XCTAssertTrue(pts.contains { hypot($0.x - a.x, $0.y - a.y) < 0.5 }, "\(name): route visits \(b.id)")
                }
            }
            // One connector per leg, with a label; a story frame exactly when the leg has a story.
            let connectors = pages.flatMap(\.connectors)
            XCTAssertEqual(connectors.map(\.legIndex).sorted(), Array(s.legs.indices), name)
            for c in connectors {
                XCTAssertNotNil(c.labelFrame, "\(name) leg \(c.legIndex) label")
                XCTAssertEqual(c.storyFrame != nil, s.legs[c.legIndex].story != nil, "\(name) leg \(c.legIndex) story")
            }
        }
    }

    // MARK: Packing

    func testNoBlockCrossesASliceEdge() {
        for (name, make) in fixtures {
            for page in stopSlices(compose(make()).1) {
                for b in page.blocks {
                    XCTAssertGreaterThanOrEqual(b.frame.minY, spec.contentRect.minY - 0.5, "\(name) \(b.id) top")
                    XCTAssertLessThanOrEqual(b.frame.maxY, spec.contentRect.maxY + 0.5, "\(name) \(b.id) bottom")
                    XCTAssertGreaterThanOrEqual(b.frame.minX, 0, "\(name) \(b.id)")
                    XCTAssertLessThanOrEqual(b.frame.maxX, page.size.width, "\(name) \(b.id)")
                }
                for c in page.connectors {
                    for r in [c.labelFrame, c.storyFrame].compactMap({ $0 }) {
                        XCTAssertTrue(CGRect(origin: .zero, size: page.size).contains(r), "\(name) leg \(c.legIndex) text inside page")
                    }
                }
            }
        }
    }

    func testEveryStopIsPlacedOnceInOrder() {
        for (name, make) in fixtures {
            let (s, doc) = compose(make())
            let order = stopSlices(doc).flatMap(\.blocks).compactMap { b -> Int? in
                if case .stop(let i, _) = b.content { i } else { nil }
            }
            XCTAssertEqual(order, Array(s.stops.indices), name)
        }
    }

    func testNoPageMoreThanAThirdEmptyExceptTheLast() {
        let content = spec.contentRect
        for (name, make) in fixtures {
            let pages = stopSlices(compose(make()).1)
            for (k, page) in pages.enumerated() {
                var bottom = page.blocks.map(\.frame.maxY).max() ?? content.minY
                for c in page.connectors {
                    bottom = max(bottom, c.center.y + 18, c.labelFrame?.maxY ?? 0, c.storyFrame?.maxY ?? 0)
                }
                let empty = (content.maxY - bottom) / content.height
                print("FILL \(name) page \(k + 1)/\(pages.count): \(Int((1 - empty) * 100))% blocks=\(page.blocks.map(\.id))")
                if k < pages.count - 1 {
                    XCTAssertLessThanOrEqual(empty, 1.0 / 3.0 + 0.01, "\(name) page \(k + 1) is \(Int(empty * 100))% empty")
                }
            }
        }
    }

    // MARK: Slice order and privacy-driven options

    func testSliceOrder() {
        let doc = compose(JourneyFixtures.fourStops()).1
        let kinds = doc.slices.map(\.kind)
        XCTAssertEqual(kinds.first, .cover)
        XCTAssertEqual(kinds[1], .map)
        XCTAssertEqual(kinds.last, .closing)
        XCTAssertTrue(kinds.dropFirst(2).dropLast().allSatisfy { $0 == .stops })
        XCTAssertEqual(doc.slices.map(\.index), Array(doc.slices.indices))
        XCTAssertTrue(doc.slices.allSatisfy { $0.size == spec.sliceSize })
    }

    func testMapSliceOmittedWhenHidden() {
        var s = JourneyFixtures.fourStops().snapshot
        s.mapMode = .hidden
        let kinds = VerticalComposer().compose(s, spec: spec).slices.map(\.kind)
        XCTAssertFalse(kinds.contains(.map))
        XCTAssertEqual(kinds.first, .cover)
        XCTAssertEqual(kinds[1], .stops)
        s.mapMode = .zoomedOut
        XCTAssertTrue(VerticalComposer().compose(s, spec: spec).slices.map(\.kind).contains(.map))
    }

    func testDeterministic() {
        let s = JourneyFixtures.eightStops().snapshot
        XCTAssertEqual(VerticalComposer().compose(s, spec: spec), VerticalComposer().compose(s, spec: spec))
    }

    func testTimeBucketAndHiddenCost() {
        var s = JourneyFixtures.fourStops().snapshot
        XCTAssertEqual(s.arrivalText(0), "08:00")
        s.stops[0].timeOfDay = .bucket(.morning)
        s.stops[0].arrivalTime = nil
        XCTAssertEqual(s.arrivalText(0), "MORNING")
        XCTAssertNil(s.stopPageModel(0).arrival)

        XCTAssertNotNil(s.stopPageModel(1).costText)
        let withCost = StopBlockLayout.make(s.stopPageModel(1), width: 595, margin: 36)
        XCTAssertTrue(StopLayout.chipText(s.stopPageModel(1))?.contains("COST") ?? false)
        s.stops[1].cost = nil
        let model = s.stopPageModel(1)
        XCTAssertNil(model.costText)
        XCTAssertFalse(StopLayout.chipText(model)?.contains("COST") ?? false)
        XCTAssertEqual(StopBlockLayout.make(model, width: 595, margin: 36).size.height, withCost.size.height,
                       accuracy: 0.5, "chip stays for time spent")
    }

    func testBlockLayoutMatchesThePageLayout() {
        // The block is the page content shifted up by the margin: same frames, no route.
        let s = JourneyFixtures.eightStops().snapshot
        for i in s.stops.indices {
            let m = s.stopPageModel(i)
            let page = StopLayout.make(m, metrics: .a4)
            let block = StopBlockLayout.make(m, width: 595, margin: 36)
            XCTAssertEqual(block.frames.ticket.offsetBy(dx: 0, dy: 36), page.ticket, "stop \(i) ticket")
            XCTAssertEqual(block.frames.hero?.offsetBy(dx: 0, dy: 36), page.hero, "stop \(i) hero")
            XCTAssertEqual(block.routeAnchor.x, page.anchor.x, accuracy: 0.001)
            XCTAssertEqual(block.routeAnchor.y + 36, page.anchor.y, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(block.size.height, block.frames.card.maxY)
            let shrunk = StopBlockLayout.make(m, width: 595, margin: 36, photoBandScale: 0.85)
            if m.photos.isEmpty {
                XCTAssertEqual(shrunk.size.height, block.size.height, "stop \(i): no photo band to shrink")
            } else {
                XCTAssertLessThan(shrunk.size.height, block.size.height, "stop \(i): 0.85 band is shorter")
            }
        }
    }

    // MARK: Snapshots

    /// Fixture ids are random UUIDs, and rotations, tape and wobble are seeded from ids: give the snapshot stable ids.
    /// Returns the map from stable photo id back to the stored one, so photos still load.
    private func stabilized(_ s: JourneySnapshot) -> (JourneySnapshot, [String: String]) {
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
    private struct RemappedProvider: StoryImageProvider {
        var base: StoryImageProvider
        var ids: [String: String]
        func image(for photo: StoryPhoto, preferThumbnail: Bool, maxPixel: Int) -> CGImage? {
            base.image(for: StoryPhoto(id: ids[photo.id] ?? photo.id, isHero: photo.isHero),
                       preferThumbnail: preferThumbnail, maxPixel: maxPixel)
        }
    }

    func testComposedPageSnapshots() throws {
        #if os(macOS)
        var missingMacReferences: [String] = []
        #endif
        for (name, make) in fixtures {
            let f = make()
            let (s, ids) = stabilized(f.snapshot)
            let doc = VerticalComposer().compose(s, spec: spec)
            let provider = RemappedProvider(base: ModelStoryImageProvider(source: ModelPhotoSource(context: f.context)), ids: ids)
            for slice in doc.slices {
                // The cover, map and closing views are covered elsewhere (and the map belongs to another change);
                // snapshot them once, for the four-stop journey.
                if slice.kind != .stops && name != "fourStops" { continue }
                if slice.kind == .map { continue }
                let view = ComposedPageView(slice: slice, snapshot: s, spec: spec)
                    .environment(\.storyImageProvider, provider)
                let img = try XCTUnwrap(TestImages.render(view, proposed: ProposedViewSize(slice.size)), "\(name) \(slice.id)")
                XCTAssertEqual(img.width, Int(slice.size.width))
                XCTAssertEqual(img.height, Int(slice.size.height))
                let snapName = "composed-\(name)-\(slice.id)"
                #if os(macOS)
                // The sandboxed macOS test host cannot write into the source tree, so it cannot record references.
                // Keep a copy in the host's temporary directory to record from by hand; compare once references exist.
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("composed-snapshots", isDirectory: true)
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
            throw XCTSkip("No macOS references yet for \(missingMacReferences.count) composed pages; copy them from "
                          + "the test host's tmp/composed-snapshots into __Snapshots__.")
        }
        #endif
    }

    // MARK: PDF

    func testEightStopPDFSizeAndPages() async throws {
        let f = JourneyFixtures.eightStops()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("vc-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let maps = MapSnapshotService(cacheDirectory: base.appendingPathComponent("maps"))
        maps.timeout = .seconds(3)
        let exporter = StoryPDFExporter(snapshots: maps, outputDirectory: base.appendingPathComponent("out"))
        let expected = exporter.document(for: f.journey).document.slices.count
        let url = try await exporter.export(f.journey)
        let doc = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(doc.pageCount, expected)
        for i in 0..<doc.pageCount {
            let box = try XCTUnwrap(doc.page(at: i)).bounds(for: .mediaBox)
            XCTAssertEqual(box.size.width, 595, accuracy: 0.5)
            XCTAssertEqual(box.size.height, 842, accuracy: 0.5)
        }
        XCTAssertTrue((doc.string ?? "").contains("Juhu Beach"), "last stop name extractable")
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        print("EIGHT_STOP_PDF_BYTES=\(size) pages=\(doc.pageCount)")
        XCTAssertLessThan(size, 4_400_000, "8-stop PDF must stay under 4.4 MB (was \(size))")
        if let dir = ProcessInfo.processInfo.environment["VC_PDF_OUT"] {
            try? FileManager.default.removeItem(atPath: dir + "/eightStops.pdf")
            try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: dir + "/eightStops.pdf"))
        }
    }
}
