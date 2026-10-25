import XCTest
import SwiftUI
import SwiftData
@testable import TravelJournal

/// Story frames (`OutputSpec.story`) from `VerticalComposer`: one stop per frame, nothing readable inside the clear bands,
/// route seams, the fit ladder, `StoryTrim`, and reference snapshots of a few frames. The A4 path is covered by
/// `VerticalComposerTests`.
@MainActor
final class StoryComposerTests: XCTestCase {
    let spec = OutputSpec.story
    let showAll = ExportPrivacy(hideStayStops: false)

    private var fixtures: [(String, () -> JourneyFixtures.Fixture)] {
        [("oneStop", JourneyFixtures.oneStop), ("fourStops", JourneyFixtures.fourStops),
         ("eightStops", JourneyFixtures.eightStops), ("noPhotos", JourneyFixtures.noPhotosStop),
         ("fourPhotos", JourneyFixtures.fourPhotosStop), ("hundredWord", JourneyFixtures.hundredWordStop),
         ("stress", JourneyFixtures.storyStressStop), ("twelve", JourneyFixtures.twelveStops)]
    }

    private func compose(_ s: JourneySnapshot) -> ComposedDocument { VerticalComposer().compose(s, spec: spec) }
    private func stopSlices(_ d: ComposedDocument) -> [ComposedSlice] { d.slices.filter { $0.kind == .stops } }

    // MARK: Structure

    func testFramesAreCoverOneStopEachClosingAndNoMap() {
        for (name, make) in fixtures {
            var s = make().snapshot
            s.mapMode = .show
            let doc = compose(s)
            let kinds = doc.slices.map(\.kind)
            XCTAssertEqual(kinds.first, .cover, name)
            XCTAssertEqual(kinds.last, .closing, name)
            XCTAssertFalse(kinds.contains(.map), "\(name): no map frame in a Story")
            XCTAssertEqual(kinds.filter { $0 == .stops }.count, s.stops.count, "\(name): one frame per stop")
            XCTAssertEqual(doc.slices.map(\.index), Array(doc.slices.indices), name)
            XCTAssertTrue(doc.slices.allSatisfy { $0.size == spec.sliceSize }, name)
            for frame in stopSlices(doc) {
                let stops = frame.blocks.compactMap { b -> Int? in if case .stop(let i, _) = b.content { i } else { nil } }
                XCTAssertEqual(stops.count, 1, "\(name) \(frame.id): exactly one stop")
            }
            let order = stopSlices(doc).flatMap(\.blocks).compactMap { b -> Int? in if case .stop(let i, _) = b.content { i } else { nil } }
            XCTAssertEqual(order, Array(s.stops.indices), name)
        }
    }

    func testDeterministic() {
        let s = JourneyFixtures.eightStops().snapshot
        XCTAssertEqual(compose(s), compose(s))
    }

    func testHiddenStayStopIsAbsent() {
        let f = JourneyFixtures.withStayStop()
        let snapshot = ExportOptions(format: .story, privacy: ExportPrivacy()).apply(to: f.snapshot)
        let doc = compose(snapshot)
        XCTAssertEqual(stopSlices(doc).count, 2, "the hotel stop gets no frame")
        let names = snapshot.stops.map(\.placeName)
        XCTAssertFalse(names.contains("Taj Mahal Palace"))
        XCTAssertEqual(doc.slices.flatMap(\.connectors).count, 1, "its legs merged into one")
        let shown = ExportOptions(format: .story, privacy: showAll).apply(to: f.snapshot)
        XCTAssertEqual(stopSlices(compose(shown)).count, 3)
    }

    // MARK: Clear bands

    func testNothingReadableInsideTheClearBands() {
        let safe = spec.safeContentRect
        XCTAssertEqual(safe.minY, 89.6, accuracy: 0.01)
        XCTAssertEqual(safe.maxY, 512, accuracy: 0.01)
        for (name, make) in fixtures {
            let doc = compose(make().snapshot)
            assertNoSliceEdgeCrossings(doc, axis: .vertical, allowed: { _ in safe.minY...safe.maxY }, name)
        }
    }

    func testEveryStopFitsAndLabelsStayInsideTheFrame() {
        for (name, make) in fixtures {
            let s = make().snapshot
            for i in s.stops.indices {
                let fit = StoryStopFit.resolve(s, spec: spec, index: i)
                XCTAssertTrue(fit.fits, "\(name) stop \(i): plan \(fit.plan) height \(fit.totalHeight)")
                XCTAssertLessThanOrEqual(fit.totalHeight, spec.safeContentRect.height, "\(name) stop \(i)")
            }
            for frame in stopSlices(compose(s)) {
                for c in frame.connectors {
                    for r in [c.labelFrame, c.storyFrame].compactMap({ $0 }) {
                        XCTAssertGreaterThanOrEqual(r.minX, 0, "\(name) leg \(c.legIndex)")
                        XCTAssertLessThanOrEqual(r.maxX, spec.sliceSize.width, "\(name) leg \(c.legIndex)")
                    }
                }
            }
        }
    }

    func testStressStopFitsByTrimming() {
        let s = JourneyFixtures.storyStressStop().snapshot
        let fit = StoryStopFit.resolve(s, spec: spec, index: 0)
        XCTAssertTrue(fit.fits)
        XCTAssertTrue(fit.plan.trimStory, "100 words cannot fit untrimmed")
        XCTAssertLessThan(fit.model.story.count, s.stops[0].story.count)
        XCTAssertTrue(s.stops[0].story.hasPrefix(fit.model.story.replacingOccurrences(of: "\u{2026}", with: "")),
                      "the trimmed story is the start of the full one")
        XCTAssertGreaterThanOrEqual(fit.model.photos.count, 1)
        // The PDF path is untouched: the model the A4 composer draws keeps the full story.
        XCTAssertEqual(s.stopPageModel(0).story, s.stops[0].story)
    }

    func testShortStopIsNotTrimmed() {
        let s = JourneyFixtures.noPhotosStop().snapshot
        let fit = StoryStopFit.resolve(s, spec: spec, index: 0)
        XCTAssertFalse(fit.plan.trimStory)
        XCTAssertEqual(fit.model.story, s.stops[0].story)
    }

    func testLadderOrder() {
        let l = StoryStopPlan.ladder
        XCTAssertFalse(l[0].trimStory)
        XCTAssertTrue(l[1].trimStory && l[1].heroScale == 1, "(a) trim first")
        XCTAssertEqual(l[2].heroScale, 0.85, "(b) photo band 0.85")
        XCTAssertEqual(l[3].maxPhotos, 2, "(c) hero + one more photo")
    }

    func testStoryTextIsLargeEnoughToRead() {
        // 3x render: 14 pt = 42 px; the story card is 16 pt (48 px) and the leg note 18 pt (54 px).
        XCTAssertGreaterThanOrEqual(StoryStopFit.storyFontSize * spec.renderScale, 40)
        XCTAssertGreaterThanOrEqual(StoryStopFit.storyFontSize, 14)
        XCTAssertGreaterThanOrEqual(18 * spec.renderScale, 40)
    }

    // MARK: Route

    func testSeamsShareTheCutPoint() {
        for (name, make) in fixtures {
            let frames = stopSlices(compose(make().snapshot))
            XCTAssertNil(frames.first?.routeEntry, name)
            XCTAssertNil(frames.last?.routeExit, name)
            for k in 0..<max(frames.count - 1, 0) {
                let a = frames[k], b = frames[k + 1]
                guard let exit = a.routeExit, let entry = b.routeEntry else { XCTFail("\(name) seam \(k)"); continue }
                XCTAssertEqual(exit.y, a.size.height, accuracy: 1, "\(name) seam \(k)")
                XCTAssertEqual(entry.y, 0, accuracy: 1, "\(name) seam \(k)")
                XCTAssertEqual(exit.x, entry.x, accuracy: 1, "\(name) seam \(k)")
                let lastPt = a.route.last?.points.last, firstPt = b.route.first?.points.first
                XCTAssertEqual(lastPt?.x ?? -1, exit.x, accuracy: 1, "\(name) seam \(k): drawn exit")
                XCTAssertEqual(lastPt?.y ?? -1, exit.y, accuracy: 1)
                XCTAssertEqual(firstPt?.x ?? -1, entry.x, accuracy: 1, "\(name) seam \(k): drawn entry")
                XCTAssertEqual(firstPt?.y ?? -1, 0, accuracy: 1)
            }
        }
    }

    func testRouteVisitsEveryPinAndEndsAtTheMarker() {
        for (name, make) in fixtures {
            let s = make().snapshot
            let frames = stopSlices(compose(s))
            for frame in frames {
                let pts = frame.route.flatMap(\.points)
                for b in frame.blocks {
                    guard case .stop = b.content, let a = b.routeAnchor else { continue }
                    XCTAssertTrue(pts.contains { hypot($0.x - a.x, $0.y - a.y) < 0.5 }, "\(name) \(b.id)")
                }
            }
            let end = frames.last?.blocks.first { $0.content == .endMarker }
            XCTAssertNotNil(end, name)
            XCTAssertEqual(frames.last?.route.last?.points.last?.y ?? -1, end?.routeAnchor?.y ?? -2, accuracy: 0.5, name)
            // One connector per leg, each in the frame of the stop it leads into.
            XCTAssertEqual(frames.flatMap(\.connectors).map(\.legIndex), Array(s.legs.indices), name)
            for (i, frame) in frames.enumerated() {
                XCTAssertEqual(frame.connectors.map(\.legIndex), i > 0 ? [i - 1] : [], "\(name) frame \(i)")
            }
        }
    }

    func testLaneRunsThroughTheBands() {
        let s = JourneyFixtures.fourStops().snapshot
        let frames = stopSlices(compose(s))
        let safe = spec.safeContentRect
        for frame in frames.dropFirst() {
            let ys = frame.route.flatMap(\.points).map(\.y)
            XCTAssertEqual(ys.min() ?? 1, 0, accuracy: 0.01)
            XCTAssertLessThan(ys.min() ?? 1, safe.minY, "the route reaches the top edge")
        }
        for frame in frames.dropLast() {
            XCTAssertEqual(frame.route.flatMap(\.points).map(\.y).max() ?? 0, spec.sliceSize.height, accuracy: 0.01)
        }
    }

    // MARK: Metrics

    func testA4MetricsAreUnchanged() {
        XCTAssertEqual(VerticalComposer.Metrics.resolved(for: .a4PDF), VerticalComposer.Metrics())
        let m = VerticalComposer.Metrics.resolved(for: spec)
        XCTAssertEqual(m.laneInset, spec.margins.left - 2)
        XCTAssertLessThan(m.badgeSide, 36)
        XCTAssertLessThanOrEqual(m.storyWidth + m.laneInset + m.badgeSide / 2 + m.textGap, spec.sliceSize.width - spec.margins.left + 0.5)
    }

    func testA4StillUsesTheClassicPathWithAMapAndPackedPages() {
        let s = JourneyFixtures.fourStops().snapshot
        let doc = VerticalComposer().compose(s, spec: .a4PDF)
        XCTAssertTrue(doc.slices.map(\.kind).contains(.map))
        XCTAssertLessThan(stopSlices(doc).count, s.stops.count, "A4 packs several stops per page")
    }

    // MARK: StoryTrim

    func testTrimTakesTheFirstSentence() {
        XCTAssertEqual(StoryTrim.firstSentence("We arrived at dawn. The tea was hot! Then we left."), "We arrived at dawn.")
        XCTAssertEqual(StoryTrim.firstSentence("Is this the place? It was."), "Is this the place?")
        XCTAssertEqual(StoryTrim.firstSentence("One sentence only"), "One sentence only")
        XCTAssertEqual(StoryTrim.firstSentence("  \n "), "")
        XCTAssertEqual(StoryTrim.firstSentence(""), "")
        XCTAssertEqual(StoryTrim.firstSentence("First line\nSecond line."), "First line")
    }

    func testTrimDoesNotSplitAbbreviationsDecimalsOrInitials() {
        XCTAssertEqual(StoryTrim.firstSentence("Dr. Mehta met us at 3.5 km from St. Xavier's. We ate."),
                       "Dr. Mehta met us at 3.5 km from St. Xavier's.")
        XCTAssertEqual(StoryTrim.firstSentence("J. K. wrote here. Nice."), "J. K. wrote here.")
        XCTAssertEqual(StoryTrim.firstSentence("He said \"stop.\" Then he left."), "He said \"stop.\"")
        XCTAssertEqual(StoryTrim.firstSentence("Wow!! Really?! Yes."), "Wow!!")
    }

    func testTrimCapsAVeryLongSentenceAtWordBoundary() {
        let long = (1...80).map { "word\($0)" }.joined(separator: " ") + "."
        let out = StoryTrim.firstSentence(long)
        XCTAssertTrue(out.hasSuffix("\u{2026}"))
        XCTAssertEqual(out.split(separator: " ").count, StoryTrim.maxWords)
        XCTAssertTrue(long.hasPrefix(String(out.dropLast())), "a prefix of the original, never mid-word")
    }

    func testTrimNeverGrowsAndIsIdempotent() {
        for text in [JourneyFixtures.hundredWordStory, "Short.", "No stop here", "A. B. C. D."] {
            let once = StoryTrim.trimmed(text)
            XCTAssertLessThanOrEqual(once.count, text.count)
            XCTAssertEqual(StoryTrim.trimmed(once), once)
        }
    }

    func testClampFitsTheLineBudget() {
        let text = JourneyFixtures.hundredWordStory
        let out = StoryTrim.clamp(text, fontName: PageFont.lora, size: 16, lineSpacing: 3.5, width: 280, maxLines: 3)
        let one = PageText.height("Ag", fontName: PageFont.lora, size: 16, lineSpacing: 0, width: 280)
        XCTAssertLessThanOrEqual(PageText.height(out, fontName: PageFont.lora, size: 16, lineSpacing: 3.5, width: 280),
                                 one * 3 + 7 + 1)
        XCTAssertTrue(out.hasSuffix("\u{2026}"))
        XCTAssertEqual(StoryTrim.clamp("Short", fontName: PageFont.lora, size: 16, lineSpacing: 3.5, width: 280, maxLines: 3), "Short")
    }

    // MARK: Snapshots

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

    private struct RemappedProvider: StoryImageProvider {
        var base: StoryImageProvider
        var ids: [String: String]
        func image(for photo: StoryPhoto, preferThumbnail: Bool, maxPixel: Int) -> CGImage? {
            base.image(for: StoryPhoto(id: ids[photo.id] ?? photo.id, isHero: photo.isHero),
                       preferThumbnail: preferThumbnail, maxPixel: maxPixel)
        }
    }

    func testStoryFrameSnapshots() throws {
        #if os(macOS)
        var missing: [String] = []
        #endif
        let wanted: [(fixture: String, kinds: Set<ComposedSlice.Kind>, indices: Set<Int>?)] = [
            ("fourStops", [.cover, .closing], nil), ("fourStops", [.stops], [2, 3]), ("stress", [.stops], nil),
            ("eightStops", [.stops], [3]),
        ]
        for w in wanted {
            let make = try XCTUnwrap(fixtures.first { $0.0 == w.fixture }).1
            let f = make()
            let (s, ids) = stabilized(f.snapshot)
            let doc = compose(s)
            let provider = RemappedProvider(base: ModelStoryImageProvider(source: ModelPhotoSource(context: f.context)), ids: ids)
            for slice in doc.slices where w.kinds.contains(slice.kind) && (w.indices?.contains(slice.index) ?? true) {
                let view = ComposedPageView(slice: slice, snapshot: s, spec: spec)
                    .environment(\.storyImageProvider, provider)
                    .environment(\.exportBrandStamp, true)
                let img = try XCTUnwrap(TestImages.render(view, proposed: ProposedViewSize(slice.size), scale: 1), slice.id)
                XCTAssertEqual(img.width, 360)
                XCTAssertEqual(img.height, 640)
                let snapName = "story-\(w.fixture)-\(slice.id)"
                #if os(macOS)
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("story-snapshots", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                TestImages.writePNG(img, to: dir.appendingPathComponent("\(snapName)-macos.png"))
                if !FileManager.default.fileExists(atPath: Snapshots.referenceURL(named: snapName).path) {
                    missing.append(snapName)
                    continue
                }
                #endif
                assertSnapshot(img, named: snapName, tolerance: 0.002)
            }
        }
        #if os(macOS)
        if !missing.isEmpty {
            throw XCTSkip("No macOS references yet for \(missing.count) Story frames; copy them from the test host's tmp/story-snapshots.")
        }
        #endif
    }
}
