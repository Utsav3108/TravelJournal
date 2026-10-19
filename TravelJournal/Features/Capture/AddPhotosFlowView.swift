import SwiftUI
import SwiftData
import PhotosUI

/// Add photos -> progress -> suggested stops review -> confirm. Calm editor style (cream paper, system controls).
struct AddPhotosFlowView: View {
    let journey: Journey
    private let photoStore: PhotoStoring?
    private let cameraProvider: (@MainActor () async -> [PhotoMeta])?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model: CaptureViewModel
    @State private var picks: [PhotosPickerItem] = []
    @State private var searchTarget: SearchTarget?
    private let autoStart: Bool

    /// - photoImporter / placeLookup: real services from the app; nil falls back to empty local stand-ins.
    /// - cameraProvider: presents the camera and returns the captured photos; nil hides the camera button.
    /// - photoStore: defaults to `FilePhotoStore()`.
    init(journey: Journey,
         photoImporter: PhotoImporting? = nil,
         placeLookup: PlaceLookup? = nil,
         cameraProvider: (@MainActor () async -> [PhotoMeta])? = nil,
         photoStore: PhotoStoring? = nil,
         autoStartPreview: Bool = false) {
        self.autoStart = autoStartPreview
        self.journey = journey
        self.photoStore = photoStore
        self.cameraProvider = cameraProvider
        _model = State(initialValue: CaptureViewModel(importer: photoImporter ?? EmptyPhotoImporter(),
                                                      lookup: placeLookup ?? EmptyPlaceLookup()))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                switch model.step {
                case .chooseSource: sourceStep
                case .importing: progressStep
                case .review: reviewStep
                case .done(let summary): doneStep(summary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .done = model.step {} else {
                        Button("Cancel") { model.cancelLookups(); dismiss() }
                    }
                }
            }
            .sheet(item: $searchTarget) { t in
                CapturePlaceSearchSheet(model: model, cardID: t.id)
            }
        }
        .tint(KraftColor.route)
        .foregroundStyle(KraftColor.ink)
        .onDisappear { model.cancelLookups() }
        .task { if autoStart, model.step == .chooseSource { await model.process(items: []) } }
    }

    private var title: String {
        switch model.step {
        case .chooseSource: "Add photos"
        case .importing: "Importing"
        case .review: "Suggested stops"
        case .done: "All set"
        }
    }

    // MARK: Step 1

    private var sourceStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52)).foregroundStyle(KraftColor.kraftDark)
            Text("We'll read the place and time from your photos and group them into stops.")
                .font(KraftFont.body(17, scaled: true)).multilineTextAlignment(.center)
            Text("Photos you saved from chat apps usually have no location. You can pick a place for those yourself.")
                .font(KraftFont.bodyItalic(14, scaled: true)).foregroundStyle(KraftColor.inkSoft)
                .multilineTextAlignment(.center)
            if let n = model.notice {
                Text(n).font(KraftFont.body(14, scaled: true)).foregroundStyle(KraftColor.route)
            }
            PhotosPicker(selection: $picks, maxSelectionCount: 20, selectionBehavior: .ordered,
                         matching: .images, photoLibrary: .shared()) {
                Label("Choose photos", systemImage: "photo.stack").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .onChange(of: picks) { _, new in
                guard !new.isEmpty else { return }
                Task { await model.process(items: new.map { AnyHashable($0) }); picks = [] }
            }
            if let cameraProvider {
                Button {
                    Task {
                        let shots = await cameraProvider()
                        if !shots.isEmpty { model.ingest(shots) }
                    }
                } label: { Label("Take a photo", systemImage: "camera").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
            }
            Spacer()
        }
        .padding(24)
    }

    // MARK: Step 2

    private var progressStep: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(model.statusText).font(KraftFont.body(16, scaled: true)).foregroundStyle(KraftColor.inkSoft)
        }
    }

    // MARK: Step 3

    private var reviewStep: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Text("Check the stops we found. Rename, merge, split or drop anything that looks wrong.")
                    .font(KraftFont.body(14, scaled: true)).foregroundStyle(KraftColor.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                    StopCardView(model: model, card: card, index: index,
                                 onFind: { searchTarget = SearchTarget(id: card.id) })
                }
                if !model.unplaced.isEmpty { UnplacedTray(model: model) }
                if model.cards.isEmpty {
                    Text("No stops left. Go back and choose photos again.")
                        .font(KraftFont.body(15, scaled: true)).foregroundStyle(KraftColor.inkSoft)
                    Button("Start over") { model.reset() }.buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            if model.canCommit {
                Button { model.commit(to: journey, editor: makeEditor()) } label: {
                    Text(model.cards.count == 1 ? "Add 1 stop" : "Add \(model.cards.count) stops").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .padding(16).background(.regularMaterial)
            }
        }
    }

    // MARK: Step 4

    private func doneStep(_ s: CommitSummary) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal").font(.system(size: 48)).foregroundStyle(KraftColor.stampTeal)
            Text("\(s.stopsCreated) stop\(s.stopsCreated == 1 ? "" : "s") added with \(s.photosSaved) photo\(s.photosSaved == 1 ? "" : "s").")
                .font(KraftFont.body(17, scaled: true)).multilineTextAlignment(.center)
            if !s.skipped.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(s.skipped.count) photo\(s.skipped.count == 1 ? "" : "s") skipped. A stop holds up to \(PhotoLimits.maxPerStop) photos.")
                        .font(KraftFont.body(14, scaled: true)).foregroundStyle(KraftColor.inkSoft)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(s.skipped) { PhotoThumb(image: model.thumbnail(for: $0), size: 56) } }
                    }
                }
            }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(24)
    }

    private func makeEditor() -> JourneyEditor {
        JourneyEditor(context: journey.modelContext ?? modelContext, photos: photoStore ?? FilePhotoStore())
    }
}

private struct SearchTarget: Identifiable { let id: UUID }

// MARK: - Pieces

struct PhotoThumb: View {
    let image: UIImage?
    var size: CGFloat = 64
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { KraftColor.paperDeep }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(KraftColor.paperEdge, lineWidth: 0.5))
    }
}

private struct StopCardView: View {
    let model: CaptureViewModel
    let card: StopCard
    let index: Int
    let onFind: () -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Stop \(index + 1)").font(KraftFont.label(12, scaled: true)).foregroundStyle(KraftColor.kraftDark)
                Spacer()
                if let a = card.cluster.arrival {
                    Text(a, style: .time).font(KraftFont.label(12, scaled: true)).foregroundStyle(KraftColor.inkSoft)
                }
                if let m = card.cluster.timeSpentMinutes {
                    Text("\(m) min").font(KraftFont.label(12, scaled: true)).foregroundStyle(KraftColor.inkSoft)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(card.photos.enumerated()), id: \.element.id) { i, p in
                        PhotoThumb(image: model.thumbnail(for: p))
                            .overlay(alignment: .bottomTrailing) {
                                if card.cluster.inferredIDs.contains(p.id) {
                                    Image(systemName: "clock").font(.caption2).padding(3)
                                        .background(.thinMaterial, in: Circle()).padding(2)
                                        .accessibilityLabel("Place inferred from time")
                                }
                            }
                            .opacity(i >= PhotoLimits.maxPerStop ? 0.45 : 1)
                            .contextMenu {
                                if card.photos.count > 1 {
                                    Button("Split into its own stop", systemImage: "scissors") {
                                        model.split(photoID: p.id, from: card.id)
                                    }
                                }
                            }
                    }
                }
            }
            if card.photos.count > PhotoLimits.maxPerStop {
                Text("Only the first \(PhotoLimits.maxPerStop) photos are kept. Split the rest into their own stops if you want them.")
                    .font(KraftFont.body(12, scaled: true)).foregroundStyle(KraftColor.inkSoft)
            }
            HStack {
                TextField("Place name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(KraftFont.body(16, scaled: true))
                    .onSubmit { model.rename(card.id, to: name) }
                    .onChange(of: name) { _, v in if v != card.name { model.rename(card.id, to: v) } }
                if card.lookup == .loading { ProgressView() }
            }
            .onAppear { name = card.name }
            .onChange(of: card.name) { _, v in if v != name { name = v } }
            if !card.hasLocation && card.place == nil {
                Text("No location in these photos. They may have been shared via a messaging app.")
                    .font(KraftFont.bodyItalic(12, scaled: true)).foregroundStyle(KraftColor.inkSoft)
            } else if card.lookup == .notFound && card.needsPlace {
                Text("We couldn't name this place.").font(KraftFont.bodyItalic(12, scaled: true))
                    .foregroundStyle(KraftColor.inkSoft)
            }
            HStack {
                Button("Find this place", systemImage: "magnifyingglass", action: onFind)
                if index > 0 {
                    Button("Merge with previous", systemImage: "arrow.triangle.merge") { model.mergeWithPrevious(card.id) }
                }
                Spacer()
                Button("Drop", systemImage: "trash", role: .destructive) { model.drop(card.id) }
            }
            .font(KraftFont.body(13, scaled: true)).buttonStyle(.bordered).controlSize(.small)
            .labelStyle(.titleOnly)
        }
        .padding(12)
        .background(KraftColor.polaroidWhite.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(KraftColor.paperEdge, lineWidth: 0.5))
    }
}

private struct UnplacedTray: View {
    let model: CaptureViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unplaced photos").font(KraftFont.label(13, scaled: true)).foregroundStyle(KraftColor.kraftDark)
            Text("No place or time. Assign each to a stop, or make it a stop of its own.")
                .font(KraftFont.body(12, scaled: true)).foregroundStyle(KraftColor.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.unplaced) { p in
                        Menu {
                            ForEach(Array(model.cards.enumerated()), id: \.element.id) { i, c in
                                Button("Add to stop \(i + 1)\(c.name.isEmpty ? "" : ": \(c.name)")") {
                                    model.assign(photoID: p.id, toCard: c.id)
                                }
                            }
                            Button("New stop from this photo") { model.newStop(fromUnplaced: p.id) }
                            Button("Discard", role: .destructive) { model.discardUnplaced(p.id) }
                        } label: { PhotoThumb(image: model.thumbnail(for: p), size: 72) }
                    }
                }
            }
        }
        .padding(12)
        .background(KraftColor.paperDeep.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CapturePlaceSearchSheet: View {
    let model: CaptureViewModel
    let cardID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PlaceCandidate] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                if searching { ProgressView() }
                ForEach(results) { r in
                    Button {
                        model.applyPlace(r, to: cardID); dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(r.name).font(KraftFont.body(16, scaled: true))
                            if let a = r.address { Text(a).font(KraftFont.body(12, scaled: true)).foregroundStyle(KraftColor.inkSoft) }
                        }
                    }
                }
                if searched && results.isEmpty && !searching {
                    Text("Nothing found. Use the name you typed instead.").foregroundStyle(KraftColor.inkSoft)
                    Button("Use \"\(query)\"") { model.rename(cardID, to: query); dismiss() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KraftColor.paper)
            .navigationTitle("Find this place")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a place")
            .onSubmit(of: .search) {
                Task {
                    searching = true
                    results = await model.search(query, near: cardID)
                    searching = false; searched = true
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Previews

@MainActor
private func previewJourney() -> (Journey, ModelContainer) {
    let c = AppContainer.make(inMemory: true)
    let j = Journey(title: "A Day in Mumbai")
    c.mainContext.insert(j)
    return (j, c)
}

#Preview("Source") {
    let (j, c) = previewJourney()
    AddPhotosFlowView(journey: j, photoImporter: MockPhotoImporter(photos: MumbaiFixtures.dayTrip()),
                      placeLookup: MockPlaceLookup(delay: .seconds(1)),
                      cameraProvider: { [] })
        .modelContainer(c)
}

#Preview("Review") {
    let (j, c) = previewJourney()
    let importer = MockPhotoImporter(photos: MumbaiFixtures.dayTrip() +
        [MumbaiFixtures.photo("x1", nil, 9, 30, jpeg: MumbaiFixtures.jpeg(seed: 7))])
    ReviewPreviewHost(journey: j, importer: importer).modelContainer(c)
}

private struct ReviewPreviewHost: View {
    let journey: Journey
    let importer: MockPhotoImporter
    var body: some View {
        AddPhotosFlowView(journey: journey, photoImporter: importer, placeLookup: MockPlaceLookup(delay: .milliseconds(600)),
                          autoStartPreview: true)
    }
}
