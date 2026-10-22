#if os(macOS)
import SwiftUI
import SwiftData

/// The Mac shelf window: a bookcase of face-out covers that reflows with the window. Search and sort always cover
/// every journey; "+N books" reveals the rest.
struct MacShelfView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openJourney) private var openJourney
    @Environment(\.newJourneyRequests) private var newJourneyRequests
    @Environment(\.syncState) private var syncState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Journey.date, order: .reverse) private var journeys: [Journey]

    @State private var query = ""
    @State private var sort: ShelfSort = .newest
    @State private var selection: UUID?
    @State private var expanded = false
    @State private var showCreate = false
    @State private var pendingDelete: Journey?
    @State private var renaming: Journey?
    @State private var renameText = ""
    @FocusState private var bookcaseFocused: Bool

    private struct Slot: Identifiable {
        let id: String
        let item: BookcaseReflow.Item
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in bookcase(size: geo.size) }
                .navigationTitle("My Stories")
                .searchable(text: $query, prompt: "Search journeys")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showCreate = true } label: { Label("New story", systemImage: "plus") }
                            .accessibilityIdentifier("newStoryToolbar")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Sort", selection: $sort) {
                                ForEach(ShelfSort.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.inline)
                        } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                        .accessibilityIdentifier("sortMenu")
                    }
                    #if DEBUG
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Add sample journey", systemImage: "wand.and.stars") { SampleData.mumbai(in: context) }
                            .accessibilityIdentifier("addSampleJourney")
                    }
                    #endif
                }
        }
        .tint(KraftColor.route)
        .focusedSceneValue(\.shelfActions, deleteAction)
        .onAppear(perform: consumeNewJourneyRequest)
        .onChange(of: newJourneyRequests?.pending) { consumeNewJourneyRequest() }
        .onChange(of: query) { expanded = false }
        #if DEBUG
        .task { debugLaunchArguments() }
        #endif
        .sheet(isPresented: $showCreate) {
            CreateJourneyView { journey in open(journey) }
                .preferredColorScheme(.light)
        }
        .confirmationDialog(
            "Delete this story?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { journey in
            Button("Delete \"\(journey.title)\"", role: .destructive) {
                if selection == journey.id { selection = nil }
                JourneyEditor(context: context, photos: ModelPhotoStore()).deleteJourney(journey)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("The story and all its stops will be removed. This can't be undone.")
        }
        .alert("Rename story", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: Bookcase

    private func bookcase(size: CGSize) -> some View {
        let shown = ShelfQuery.apply(journeys.libraryStories, query: query, sort: sort)
        let reflow = BookcaseReflow.layout(count: shown.count, size: size, expanded: expanded)
        let byID = Dictionary(journeys.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let slots = reflow.items.map { item -> Slot in
            switch item {
            case .book(let i): Slot(id: shown[i].id.uuidString, item: item)
            case .more: Slot(id: "more", item: item)
            case .less: Slot(id: "less", item: item)
            }
        }
        return ScrollViewReader { proxy in
            ScrollView {
                BookcaseLayout(reflow: reflow, minHeight: size.height) {
                    ForEach(slots) { slot in
                        slotView(slot, shown: shown, byID: byID)
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: reflow)
                .background {
                    ShelfWall(rows: reflow.wallRows)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = nil; bookcaseFocused = true }
                }
            }
            .background(PaperBackground())
            .focusable()
            .focusEffectDisabled()
            .focused($bookcaseFocused)
            .onKeyPress(phases: [.down, .repeat]) { press in
                handle(press, shown: shown, reflow: reflow, proxy: proxy)
            }
            .overlay { emptyState(libraryIsEmpty: journeys.isEmpty, noMatches: shown.isEmpty && !journeys.isEmpty) }
        }
    }

    @ViewBuilder
    private func slotView(_ slot: Slot, shown: [LibraryStory], byID: [UUID: Journey]) -> some View {
        switch slot.item {
        case .book(let i):
            if let journey = byID[shown[i].id] {
                ShelfBookView(journey: journey, selected: selection == journey.id)
                    .onTapGesture(count: 2) { open(journey) }
                    .onTapGesture { selection = journey.id; bookcaseFocused = true }
                    .contextMenu {
                        Button("Open") { open(journey) }
                        Button("Rename…") { startRename(journey) }
                        Divider()
                        Button("Delete…", role: .destructive) { pendingDelete = journey }
                    }
            }
        case .more(let hidden):
            ShelfTileView(title: "+\(hidden) books", hint: "Shows every shelf") { expanded = true }
        case .less:
            ShelfTileView(title: "Show less", hint: "Collapses the bookcase") { expanded = false }
        }
    }

    @ViewBuilder
    private func emptyState(libraryIsEmpty: Bool, noMatches: Bool) -> some View {
        if libraryIsEmpty && syncState == .importingFirstTime {
            VStack(spacing: 12) {
                ProgressView()
                Text("Bringing in your journeys from iCloud…")
            }
            .shelfNotice()
        } else if libraryIsEmpty {
            Text("Drag photos here, or press ⌘N to start your first journey.")
                .shelfNotice()
        } else if noMatches {
            Text("No journeys match '\(query.trimmingCharacters(in: .whitespacesAndNewlines))'.")
                .shelfNotice()
        }
    }

    // MARK: Keyboard

    private func handle(_ press: KeyPress, shown: [LibraryStory], reflow: BookcaseReflow, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard press.modifiers.isEmpty else { return .ignored }
        let direction: BookcaseReflow.Direction
        switch press.key {
        case .leftArrow: direction = .left
        case .rightArrow: direction = .right
        case .upArrow: direction = .up
        case .downArrow: direction = .down
        case .return:
            guard let journey = selectedJourney else { return .ignored }
            open(journey)
            return .handled
        default: return .ignored
        }
        let current = selection.flatMap { id in shown.firstIndex { $0.id == id } }
        guard let next = BookcaseReflow.moveSelection(from: current, direction: direction, perShelf: reflow.perShelf,
                                                      bookCount: reflow.visibleBookCount) else { return .ignored }
        selection = shown[next].id
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(shown[next].id.uuidString) }
        return .handled
    }

    // MARK: Actions

    private var selectedJourney: Journey? { journeys.first { $0.id == selection } }

    /// Published only while the bookcase has focus, so ⌘⌫ still edits text in the search field.
    private var deleteAction: ShelfActions? {
        guard bookcaseFocused, let journey = selectedJourney else { return nil }
        return ShelfActions(deleteSelected: { pendingDelete = journey })
    }

    private func open(_ journey: Journey) { openJourney?(journey) }

    private func startRename(_ journey: Journey) {
        renameText = journey.title
        renaming = journey
    }

    private func commitRename() {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let journey = renaming, !title.isEmpty {
            journey.title = title
            journey.updatedAt = .now
        }
        renaming = nil
    }

    private func consumeNewJourneyRequest() {
        guard let requests = newJourneyRequests, requests.pending else { return }
        requests.pending = false
        showCreate = true
    }

    #if DEBUG
    /// Debug launch args: -seedSample (one story), -seedLibrary N (N stories), -openSample (open the first story).
    private func debugLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-seedSample"), journeys.isEmpty { SampleData.mumbai(in: context) }
        SampleData.seedFromLaunchArguments(in: context)
        if args.contains("-openSample") {
            let journey = journeys.first ?? SampleData.mumbai(in: context)
            open(journey)
        }
    }
    #endif
}

private extension View {
    /// The one-line message on an empty or filtered-out shelf.
    func shelfNotice() -> some View {
        font(KraftFont.body(18))
            .foregroundStyle(KraftColor.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KraftColor.paper.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KraftColor.paperEdge, lineWidth: 0.8))
            .frame(maxWidth: 420)
    }
}
#endif
