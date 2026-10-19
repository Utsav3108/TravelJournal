import SwiftUI
import SwiftData

struct JourneyDetailView: View {
    let journeyID: PersistentIdentifier
    @Environment(\.modelContext) private var context

    var body: some View {
        if let journey = context.model(for: journeyID) as? Journey {
            JourneyDetailContent(journey: journey)
        } else {
            ContentUnavailableView("Story not found", systemImage: "book.closed")
        }
    }
}

private enum DetailDestination: Hashable {
    case stop(Stop)
    case newStop
    case leg(Leg)
}

struct JourneyDetailContent: View {
    @Bindable var journey: Journey
    @Environment(\.modelContext) private var context
    @Environment(\.editorPhotoStore) private var photoStore
    @Environment(\.servicePlaceLookup) private var placeLookup

    @State private var showAddPhotos = false
    @State private var destination: DetailDestination?
    @State private var pendingDelete: Stop?
    @State private var pendingMove: PendingMove?
    @State private var editMode: EditMode = .inactive

    private struct PendingMove { let from: IndexSet; let to: Int }

    private var editor: JourneyEditor { JourneyEditor(context: context, photos: photoStore) }

    var body: some View {
        let stops = journey.orderedStops
        List {
            headerSection
            Section {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    VStack(alignment: .leading, spacing: 0) {
                        StopRow(stop: stop, number: index + 1) { destination = .stop(stop) }
                        if let leg = stop.outgoingLeg, index < stops.count - 1 {
                            LegRow(leg: leg) { destination = .leg(leg) }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete { offsets in
                    guard let i = offsets.first, i < stops.count else { return }
                    requestDelete(stops[i], ordered: stops)
                }
                .onMove { from, to in
                    if EditorLogic.legsLost(moving: from, to: to, in: stops).isEmpty {
                        editor.moveStops(in: journey, from: from, to: to)
                    } else {
                        pendingMove = PendingMove(from: from, to: to)
                    }
                }
                Button { destination = .newStop } label: {
                    Label("Add stop manually", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("addStopManually")
                .listRowBackground(Color.clear)
            } header: {
                Text("Stops").stampLabel(12).foregroundStyle(KraftColor.inkSoft)
            }
        }
        .listStyle(.insetGrouped)
        .calmForm()
        .environment(\.editMode, $editMode)
        .navigationTitle(journey.title.isEmpty ? "Story" : journey.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddPhotos = true } label: { Label("Add photos", systemImage: "photo.badge.plus") }
                    .accessibilityIdentifier("addPhotos")
            }
            ToolbarItem(placement: .secondaryAction) { EditButton() }
        }
        .sheet(isPresented: $showAddPhotos) { AddPhotosFlowView(journey: journey, photoImporter: PhotoLibraryImporter(), placeLookup: placeLookup, photoStore: photoStore) }
        .navigationDestination(item: $destination) { dest in
            switch dest {
            case .stop(let s): StopEditorView(journey: journey, stop: s)
            case .newStop: StopEditorView(journey: journey, stop: nil)
            case .leg(let l): LegEditorView(leg: l)
            }
        }
        .confirmationDialog("Delete this stop?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible, presenting: pendingDelete) { stop in
            Button("Delete \"\(stop.placeName)\"", role: .destructive) {
                editor.deleteStop(stop, in: journey); pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { stop in
            let n = EditorLogic.legsLost(deleting: stop, from: journey.orderedStops).count
            Text("\(n) travel \(n == 1 ? "leg has" : "legs have") details that will be removed too.")
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
            Text("Travel legs between stops that are no longer neighbours will be removed.")
        }
    }

    private func requestDelete(_ stop: Stop, ordered: [Stop]) {
        if EditorLogic.needsDeleteConfirmation(deleting: stop, from: ordered) {
            pendingDelete = stop
        } else {
            editor.deleteStop(stop, in: journey)
        }
    }

    private var headerSection: some View {
        Section {
            TextField("Title", text: $journey.title)
                .font(KraftFont.stopName(30, scaled: true))
                .foregroundStyle(KraftColor.ink)
            DatePicker("Date", selection: $journey.date, displayedComponents: .date)
            TextField("City", text: Binding(
                get: { journey.city ?? "" }, set: { journey.city = $0.isEmpty ? nil : $0 }))
            TextField("Intro note", text: Binding(
                get: { journey.introNote ?? "" }, set: { journey.introNote = $0.isEmpty ? nil : $0 }),
                axis: .vertical)
                .lineLimit(2...6)
            TextField("Closing note", text: Binding(
                get: { journey.closingNote ?? "" }, set: { journey.closingNote = $0.isEmpty ? nil : $0 }),
                axis: .vertical)
                .lineLimit(2...6)
        }
        .listRowBackground(KraftColor.paperDeep.opacity(0.55))
        .foregroundStyle(KraftColor.ink)
    }
}

private struct StopRow: View {
    let stop: Stop
    let number: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(KraftFont.label(13, scaled: true))
                    .foregroundStyle(KraftColor.polaroidWhite)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(KraftColor.route))
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.placeName.isEmpty ? "Untitled stop" : stop.placeName)
                        .font(KraftFont.body(17, scaled: true))
                        .foregroundStyle(KraftColor.ink)
                    HStack(spacing: 6) {
                        if let c = stop.category {
                            CategoryIcon(category: EditorLogic.kraft(c), size: 16)
                        }
                        Text(subtitle).font(.footnote).foregroundStyle(KraftColor.inkSoft)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(KraftColor.inkSoft)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop \(number), \(stop.placeName)")
    }

    private var subtitle: String {
        var parts: [String] = []
        if let t = stop.arrivalTime { parts.append(t.formatted(date: .omitted, time: .shortened)) }
        let n = stop.photos.count
        parts.append("\(n) photo\(n == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}

private struct LegRow: View {
    let leg: Leg
    let open: () -> Void

    var body: some View {
        let summary = EditorLogic.legSummary(leg)
        Button(action: open) {
            HStack(spacing: 8) {
                Rectangle().fill(KraftColor.route.opacity(0.5)).frame(width: 2, height: 28)
                    .padding(.leading, 13)
                if leg.modeWasChosen {
                    TransportIcon(mode: EditorLogic.kraft(leg.mode), size: 20)
                } else {
                    Image(systemName: "arrow.down").font(.footnote).foregroundStyle(KraftColor.inkSoft)
                }
                Text(summary ?? "Add travel details")
                    .font(KraftFont.note(17, scaled: true))
                    .foregroundStyle(summary == nil ? KraftColor.inkSoft : KraftColor.ink)
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary ?? "Add travel details")
    }
}

#Preview("Journey detail") {
    let container = AppContainer.make(inMemory: true)
    let journey = SampleData.mumbai(in: container.mainContext)
    return NavigationStack { JourneyDetailView(journeyID: journey.persistentModelID) }
        .modelContainer(container)
}
