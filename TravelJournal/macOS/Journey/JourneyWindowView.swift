#if os(macOS)
import SwiftUI

/// A journey window: sidebar (map + stops) and the story strip. Edit swaps the strip for the existing list editor
/// until the inspector arrives; Done returns to the strip.
struct JourneyWindowView: View {
    @Bindable var journey: Journey

    @State private var model = JourneyWindowModel()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isEditing = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            JourneySidebar(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            if isEditing {
                NavigationStack {
                    JourneyDetailContent(journey: journey)
                        .environment(\.readStory, { isEditing = false })
                        .appDestinations()
                }
            } else {
                JourneyStripView(model: model)
            }
        }
        .navigationTitle(journey.title.isEmpty ? "Story" : journey.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    .accessibilityIdentifier("editJourney")
            }
            JourneyExportToolbar(journey: journey)
        }
        .journeyExportPresentations(journey: journey)
        .storyPhotosFromModel()
        .measuringStatusBarInset()
        .tint(KraftColor.route)
        .onAppear { model.rebuild(from: journey) }
        .onChange(of: isEditing) { _, editing in if !editing { model.rebuild(from: journey) } }
        .focusedSceneValue(\.journeySelection, JourneyWindowSelection(
            journeyID: journey.id, selectedStopID: model.selectedStopID.flatMap(UUID.init(uuidString:))))
        .focusedSceneValue(\.stripActions, isEditing ? nil : StripActions(
            zoomIn: model.zoomIn, zoomOut: model.zoomOut, fit: model.fit,
            previousStop: { model.step(-1) }, nextStop: { model.step(1) }))
    }
}
#endif
