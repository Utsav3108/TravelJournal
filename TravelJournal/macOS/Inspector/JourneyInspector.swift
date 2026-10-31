#if os(macOS)
import SwiftUI
import SwiftData

/// The right-hand inspector: edits whatever is selected (a leg, a stop, else the journey itself) and applies changes
/// live. The forms are the iPhone's, shared; this file only picks one and wires in undo and delete.
struct JourneyInspector: View {
    let journey: Journey
    let model: JourneyWindowModel
    let requestDelete: (Stop) -> Void

    var body: some View {
        switch model.inspectorTarget {
        case .leg(let id):
            if let leg = journey.orderedLegs.first(where: { "leg-" + $0.id.uuidString == id }) {
                LegInspector(leg: leg).id(id)
            } else {
                JourneyInspectorForm(journey: journey)
            }
        case .stop(let id):
            if let stop = journey.stops.first(where: { $0.id.uuidString == id }) {
                StopInspector(stop: stop, journey: journey, model: model, focusName: model.justAddedStopID == id,
                              onDelete: { requestDelete(stop) })
                    .id(id)
            } else {
                JourneyInspectorForm(journey: journey)
            }
        case .journey:
            JourneyInspectorForm(journey: journey)
        }
    }
}

private struct JourneyInspectorForm: View {
    let journey: Journey

    var body: some View {
        Form {
            JourneyFieldsSection(journey: journey)
            MapLocationSection(journey: journey)
            JourneyExportPrivacySection(journey: journey)
        }
        .calmForm()
        .undoTracked(JourneyContent(journey), target: journey) { $0.apply(to: journey) }
        .accessibilityIdentifier("journeyInspector")
    }
}

private struct StopInspector: View {
    let stop: Stop
    let journey: Journey
    let model: JourneyWindowModel
    let focusName: Bool
    let onDelete: () -> Void

    @Environment(\.editorPhotoStore) private var photoStore
    @State private var costText = ""
    @State private var minutesText = ""
    @State private var showPlaceSearch = false

    var body: some View {
        StopFormView(stop: stop, journey: journey, costText: $costText, minutesText: $minutesText,
                     showPlaceSearch: $showPlaceSearch, photoStore: photoStore, canEditPhotos: true,
                     focusNameOnAppear: focusName, voice: voiceHooks)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Button("Delete Stop…", role: .destructive, action: onDelete)
                        .accessibilityIdentifier("deleteStop")
                    Spacer()
                }
                .padding(12)
                .background(.bar)
            }
            .sheet(isPresented: $showPlaceSearch) {
                PlaceSearchSheet(stop: stop).preferredColorScheme(.light)
            }
            .onAppear(perform: syncTexts)
            // Undo/redo can change the amount or minutes from outside the text fields.
            .onChange(of: stop.costAmount) { _, new in
                if EditorLogic.parseAmount(costText) != new { costText = new.map { "\($0)" } ?? "" }
            }
            .onChange(of: stop.timeSpentMinutes) { _, new in
                if EditorLogic.parseMinutes(minutesText) != new { minutesText = new.map(String.init) ?? "" }
            }
            .undoTracked(StopContent(stop), target: stop) { $0.apply(to: stop) }
            .accessibilityIdentifier("stopInspector")
    }

    private var voiceHooks: StopVoiceHooks? {
        guard let voice = model.voice else { return nil }
        return StopVoiceHooks(isListening: voice.phase == .listening,
                              freshKeys: Set(voice.freshFields.map(\.rawValue)),
                              press: model.voicePress, release: model.voiceRelease)
    }

    private func syncTexts() {
        costText = stop.costAmount.map { "\($0)" } ?? ""
        minutesText = stop.timeSpentMinutes.map(String.init) ?? ""
    }
}

private struct LegInspector: View {
    let leg: Leg

    var body: some View {
        LegEditorView(leg: leg)
            .undoTracked(LegContent(leg), target: leg) { $0.apply(to: leg) }
            .accessibilityIdentifier("legInspector")
    }
}

// MARK: Undo

private struct UndoTracking<S: Equatable>: ViewModifier {
    let snapshot: S
    let target: AnyObject
    let apply: (S) -> Void

    @Environment(\.undoManager) private var undoManager
    @State private var tracker: EditUndoTracker<S>

    init(snapshot: S, target: AnyObject, apply: @escaping (S) -> Void) {
        self.snapshot = snapshot
        self.target = target
        self.apply = apply
        _tracker = State(initialValue: EditUndoTracker(initial: snapshot))
    }

    func body(content: Content) -> some View {
        content.onChange(of: snapshot) { _, new in
            tracker.observe(new, manager: undoManager, target: target, apply: apply)
        }
    }
}

extension View {
    /// Registers undo steps with the window's undo manager for edits to `target`, described by value snapshots.
    func undoTracked<S: Equatable>(_ snapshot: S, target: AnyObject, apply: @escaping (S) -> Void) -> some View {
        modifier(UndoTracking(snapshot: snapshot, target: target, apply: apply))
    }
}
#endif
