#if os(macOS)
import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import TravelJournal

/// Hosts the real journey window off screen and walks the "select a stop, press Edit" sequence, checking that the
/// window's content never grows past the window (the sidebar/inspector "scrolled up" bug) and that AppKit doesn't hit
/// its layout-pass limit.
@MainActor
final class JourneyWindowLayoutTests: XCTestCase {
    private var container: ModelContainer!
    private var window: NSWindow!

    private func makeJourney() -> Journey {
        container = AppContainer.make(inMemory: true)
        let context = container.mainContext
        let journey = Journey(title: "A Day in Mumbai")
        context.insert(journey)
        let editor = JourneyEditor(context: context, photos: NoopPhotoStore())
        for (n, story) in [("Chhatrapati Shivaji Terminus", "The morning light hits the Gothic arches."),
                           ("Sardar Pav Bhaji", ""), ("Siddhivinayak Temple", ""), ("Hotel check-in", "")] {
            editor.addStop(Stop(placeName: n, story: story), to: journey)
        }
        return journey
    }

    private func host(_ journey: Journey, model: JourneyWindowModel) {
        let hosting = NSHostingController(rootView: JourneyWindowView(journey: journey, model: model)
            .modelContainer(container))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1470, height: 900),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1470, height: 900))
        window.orderFront(nil)
    }

    private func settle(_ seconds: TimeInterval = 0.6) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            window.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// Frames of the window's split-view panes (not scroll content), plus what the window thinks it needs.
    private func report(_ label: String) -> String {
        var lines = ["[\(label)] window=\(window.frame.size) content=\(window.contentView!.frame.size) fitting=\(window.contentView!.fittingSize) min=\(window.contentMinSize)"]
        func walk(_ v: NSView, _ depth: Int) {
            if v is NSSplitView || v.superview is NSSplitView || String(describing: type(of: v)).contains("Inspector") {
                lines.append(String(repeating: "  ", count: depth) + "\(type(of: v)) \(v.frame.integral)")
            }
            v.subviews.forEach { walk($0, depth + 1) }
        }
        walk(window.contentView!, 0)
        return lines.joined(separator: "\n")
    }

    /// Tallest pane inside a split view, which is what pushes the window content up when it overflows.
    private func panesOverflow() -> CGFloat {
        var worst: CGFloat = 0
        func walk(_ v: NSView) {
            if v.superview is NSSplitView { worst = max(worst, v.frame.height - window.contentView!.frame.height) }
            v.subviews.forEach(walk)
        }
        walk(window.contentView!)
        return worst
    }

    @MainActor private func runScenario(voice: Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let journey = makeJourney()
        let model = JourneyWindowModel()
        if voice {
            model.voice = VoiceDictationController(capture: NoopCapture(), extractor: NoopExtractor(), isAvailable: true)
        }
        host(journey, model: model)
        await settle()
        let limit = window.contentView!.frame.height + 2
        print(report("closed voice=\(voice)"))

        model.rebuild(from: journey)
        model.select(journey.orderedStops[0].id.uuidString, center: false)
        await settle()
        print(report("selected"))

        model.inspectorShown = true
        await settle(1.0)
        print(report("edit"))
        XCTAssertLessThanOrEqual(panesOverflow(), 1, report("edit voice=\(voice)"), file: file, line: line)
        XCTAssertEqual(window.contentView!.frame.height, limit - 2, accuracy: 0.5, file: file, line: line)

        guard voice else { return }
        XCTAssertNotNil(model.voiceStop, "the voice card should be showing", file: file, line: line)
        model.voicePress()   // listening: long live transcript
        await settle(0.8)
        XCTAssertEqual(model.voice?.phase, .listening, file: file, line: line)
        XCTAssertEqual(window.contentView!.frame.height, limit - 2, accuracy: 0.5, "listening", file: file, line: line)
        model.voiceRelease()   // processing, then "found nothing" error text
        await settle(0.8)
        XCTAssertEqual(window.contentView!.frame.height, limit - 2, accuracy: 0.5, "after result", file: file, line: line)
    }

    func testEditModeWithoutVoiceKeepsLayoutInsideTheWindow() async { await runScenario(voice: false) }
    func testEditModeWithVoiceKeepsLayoutInsideTheWindow() async { await runScenario(voice: true) }
}

@MainActor
private final class NoopCapture: SpeechCapturing {
    func start() async throws -> AsyncStream<String> {
        AsyncStream { c in c.yield(String(repeating: "we reached the terminal around nine and it was lovely ", count: 12)) }
    }
    func finish() async throws -> String { "we reached the terminal around nine" }
    func cancel() {}
}

private struct NoopExtractor: DraftExtracting {
    func extract(from transcript: String) async throws -> VoiceStopDraft { VoiceStopDraft() }
}
#endif
