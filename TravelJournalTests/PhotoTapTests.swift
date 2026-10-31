#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import TravelJournal

/// Hosts a page off screen and reads where each photo's tap area sits: it must be the photo itself.
/// (Regression: every photo on a stop opened the same one, because each tap area covered the whole page, and the
/// cover's photos were not tappable at all.)
@MainActor
final class PhotoTapTests: XCTestCase {
    private let metrics = PageMetrics.phone(CGSize(width: 520, height: 780))
    private var window: NSWindow!
    private var tapped: [String] = []

    private func photos(_ n: Int) -> [StoryPhoto] { (1...n).map { StoryPhoto(id: "photo-\($0)", isHero: $0 == 1) } }

    private var frames: [String: CGRect] = [:]

    private func host(_ page: StoryPage) async {
        let view = StoryPageView(page: page, metrics: metrics,
                                 callbacks: StoryPageCallbacks(onPhotoTap: { [unowned self] in tapped.append($0.id) }))
            .onPreferenceChange(PhotoTapFrames.self) { [unowned self] in frames = $0 }
            .frame(width: metrics.size.width, height: metrics.size.height)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: metrics.size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        for _ in 0..<10 { window.contentView?.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(30)) }
    }

    /// The tap area of photo `n` must be that photo's own frame (within a point or two), not the page.
    private func assertTapArea(of n: Int, is rect: CGRect, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let f = frames["photo-\(n)"] else {
            return XCTFail("\(what) \(n) has no tap area; known: \(frames.keys.sorted())", file: file, line: line)
        }
        XCTAssertEqual(f.size.width, rect.width, accuracy: 2, "\(what) \(n) tap area is \(f), photo is \(rect)", file: file, line: line)
        XCTAssertEqual(f.size.height, rect.height, accuracy: 2, "\(what) \(n) tap area is \(f), photo is \(rect)", file: file, line: line)
        XCTAssertEqual(f.midX, rect.midX, accuracy: 2, file: file, line: line)
        XCTAssertEqual(f.midY, rect.midY, accuracy: 2, file: file, line: line)
    }

    private func stopModel(photoCount: Int) -> StopPageModel {
        StopPageModel(id: "stop-a", stopID: "a", index: 0, total: 1, name: "Times Square", story: "Loud and bright.", highlight: nil,
                      rating: 3, review: nil, categoryRaw: "landmark", arrival: nil, spentMinutes: nil, costText: nil,
                      photos: photos(photoCount), template: StopTemplate(rawValue: photoCount) ?? .t3, seed: 1,
                      entry: nil, exit: nil, inLeg: nil, outLeg: nil, hasSeal: false)
    }

    func testEachPhotoOnAStopHasItsOwnTapArea() async throws {
        let model = stopModel(photoCount: 3)
        let layout = StopLayout.make(model, metrics: metrics)
        await host(.stop(model))
        let rects = [try XCTUnwrap(layout.hero)] + layout.taped
        XCTAssertEqual(rects.count, 3)
        for (i, r) in rects.enumerated() { assertTapArea(of: i + 1, is: r, "photo") }
    }

    func testEachPhotoOnTheCoverHasItsOwnTapArea() async throws {
        let model = CoverModel(title: "One Big Day in New York", dateText: "24 OCT 2026", city: "New York",
                               postmark: "ARRIVED · 24 OCT 2026 · NEW YORK", heroPhotos: photos(3), intro: nil, seed: 1)
        let layout = CoverLayout.make(model, metrics: metrics)
        await host(.cover(model))
        let rects = [try XCTUnwrap(layout.hero)] + layout.taped
        XCTAssertEqual(rects.count, 3)
        for (i, r) in rects.enumerated() { assertTapArea(of: i + 1, is: r, "cover photo") }
    }
}
#endif
