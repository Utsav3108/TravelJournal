#if os(macOS)
import SwiftUI
import SwiftData

/// A journey window: sidebar (map + stops), the story strip, and a right-hand inspector that edits the selection.
/// Edit / Done and ⌥⌘I show and hide the inspector. Add, move and delete stops go through `JourneyEditor` with the
/// window's undo manager.
struct JourneyWindowView: View {
    @Bindable var journey: Journey

    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Environment(\.editorPhotoStore) private var photoStore
    @Environment(\.servicePlaceLookup) private var placeLookup
    @Environment(\.newJourneyRequests) private var newJourneyRequests

    @State private var model = JourneyWindowModel()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var pendingDelete: Stop?
    @State private var pendingMove: PendingMove?
    @State private var showImport = false

    private struct PendingMove { let from: IndexSet; let to: Int }

    private var editor: JourneyEditor { JourneyEditor(context: context, photos: photoStore, undoManager: undoManager) }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            JourneySidebar(model: model, onAddStop: addStop)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            JourneyStripView(model: model)
        }
        .inspector(isPresented: Binding(get: { model.inspectorShown }, set: { model.inspectorShown = $0 })) {
            JourneyInspector(journey: journey, model: model, requestDelete: requestDelete)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
        .navigationTitle(journey.title.isEmpty ? "Story" : journey.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addStop() } label: { Label("Add Stop", systemImage: "plus") }
                    .help("Add a stop")
                    .accessibilityIdentifier("addStop")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(model.inspectorShown ? "Done" : "Edit") { model.inspectorShown.toggle() }
                    .accessibilityIdentifier("editJourney")
            }
            JourneyExportToolbar(journey: journey)
        }
        .journeyExportPresentations(journey: journey)
        .storyPhotosFromModel()
        .measuringStatusBarInset()
        .tint(KraftColor.route)
        .onAppear {
            model.rebuild(from: journey)
            if newJourneyRequests?.importOnOpen.remove(journey.id) != nil { showImport = true }
            #if DEBUG
            // Debug launch args: -showInspector, -selectStop N (0-based)
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-showInspector") { model.inspectorShown = true }
            if let i = args.firstIndex(of: "-selectStop"), args.indices.contains(i + 1), let n = Int(args[i + 1]),
               journey.orderedStops.indices.contains(n) {
                model.select(journey.orderedStops[n].id.uuidString, center: false)
            }
            #endif
        }
        // Any edit (inspector, undo, import, reorder) changes what the strip shows.
        .onChange(of: JourneyWindowModel.signature(of: journey)) { model.rebuild(from: journey) }
        .sheet(isPresented: $showImport) {
            AddPhotosFlowView(journey: journey, photoImporter: PhotoLibraryImporter(), placeLookup: placeLookup,
                              photoStore: photoStore)
                .frame(minWidth: 720, minHeight: 560)
                .preferredColorScheme(.light)
        }
        .confirmationDialog("Delete this stop?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible, presenting: pendingDelete) { stop in
            Button("Delete \"\(stop.placeName.isEmpty ? "Untitled stop" : stop.placeName)\"", role: .destructive) {
                delete(stop); pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { stop in
            let n = EditorLogic.legsLost(deleting: stop, from: journey.orderedStops).count
            Text("\(n) travel \(n == 1 ? "leg has" : "legs have") details that will be removed too. You can undo this.")
        }
        .confirmationDialog("Reorder stops?", isPresented: Binding(
            get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }),
            titleVisibility: .visible) {
            Button("Reorder and discard travel details", role: .destructive) {
                if let m = pendingMove { editor.moveStops(in: journey, from: m.from, to: m.to) }
                pendingMove = nil
            }
            Button("Cancel", role: .cancel) { pendingMove = nil }
        } message: {
            Text("Travel legs between stops that are no longer neighbours will be removed. You can undo this.")
        }
        .focusedSceneValue(\.journeySelection, JourneyWindowSelection(
            journeyID: journey.id, selectedStopID: model.selectedStopID.flatMap(UUID.init(uuidString:))))
        .focusedSceneValue(\.journeyActions, journeyActions)
        .focusedSceneValue(\.stripActions, StripActions(
            zoomIn: model.zoomIn, zoomOut: model.zoomOut, fit: model.fit,
            previousStop: { model.step(-1) }, nextStop: { model.step(1) }))
    }

    // MARK: Actions

    private var journeyActions: JourneyActions {
        let stops = journey.orderedStops
        let index = model.selectedStopID.flatMap { id in stops.firstIndex { $0.id.uuidString == id } }
        var earlier: (() -> Void)?
        var later: (() -> Void)?
        if let i = index {
            if i > 0 { earlier = { move(from: i, by: -1) } }
            if i < stops.count - 1 { later = { move(from: i, by: 1) } }
        }
        return JourneyActions(
            addStop: addStop,
            importPhotos: { showImport = true },
            showDetails: model.showJourneyDetails,
            toggleInspector: { model.inspectorShown.toggle() },
            inspectorShown: model.inspectorShown,
            deleteSelectedStop: index.map { i in { requestDelete(stops[i]) } },
            moveSelectedStopEarlier: earlier,
            moveSelectedStopLater: later)
    }

    /// Inserts an untitled stop after the selected one (else at the end) and opens it in the inspector, name focused.
    private func addStop() {
        let stops = journey.orderedStops
        let index = JourneyWindowModel.insertionIndex(selectedStopID: model.selectedStopID,
                                                      stopIDs: stops.map { $0.id.uuidString })
        let stop = Stop(placeName: "")
        editor.addStop(stop, to: journey, at: index)
        model.rebuild(from: journey)
        model.justAddedStopID = stop.id.uuidString
        model.inspectorShown = true
        model.select(stop.id.uuidString)
    }

    private func requestDelete(_ stop: Stop) {
        if EditorLogic.needsDeleteConfirmation(deleting: stop, from: journey.orderedStops) {
            pendingDelete = stop
        } else {
            delete(stop)
        }
    }

    private func delete(_ stop: Stop) {
        if model.selectedStopID == stop.id.uuidString { model.select(nil) }
        editor.deleteStop(stop, in: journey)
        model.rebuild(from: journey)
    }

    /// Move Stop Earlier / Later. `to` follows SwiftUI's `move(fromOffsets:toOffset:)`: one place later is `index + 2`.
    private func move(from index: Int, by delta: Int) {
        let to = delta < 0 ? index - 1 : index + 2
        let from = IndexSet(integer: index)
        if EditorLogic.legsLost(moving: from, to: to, in: journey.orderedStops).isEmpty {
            editor.moveStops(in: journey, from: from, to: to)
        } else {
            pendingMove = PendingMove(from: from, to: to)
        }
    }
}
#endif
