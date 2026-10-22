#if os(macOS)
import SwiftUI
import AppKit

/// AppKit edge: a plain mouse wheel only produces vertical scroll events, which a horizontal strip ignores. While the
/// pointer is over this view's area, vertical wheel events (not trackpad gestures, which have precise deltas and scroll
/// sideways on their own) are re-issued as horizontal ones.
struct WheelScrollBridge: NSViewRepresentable {
    var isEnabled: Bool

    func makeNSView(context: Context) -> NSView { context.coordinator.view }

    func updateNSView(_ view: NSView, context: Context) { context.coordinator.isEnabled = isEnabled }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor
    final class Coordinator {
        let view = NSView()
        var isEnabled = true
        private var monitor: Any?

        init() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.convert(event) ?? event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func convert(_ event: NSEvent) -> NSEvent {
            guard isEnabled, !event.hasPreciseScrollingDeltas, event.phase == [], event.momentumPhase == [],
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  let window = view.window, event.window === window,
                  view.bounds.contains(view.convert(event.locationInWindow, from: nil)),
                  let cg = event.cgEvent?.copy() else { return event }
            let line = cg.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let point = cg.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let fixed = cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            cg.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
            cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
            cg.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: line)
            cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: point)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed)
            return NSEvent(cgEvent: cg) ?? event
        }
    }
}
#endif
