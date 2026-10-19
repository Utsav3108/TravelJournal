import SwiftUI
import SwiftData

struct StopEditorView: View {
    let journey: Journey
    /// nil = creating a new stop (inserted on Save through JourneyEditor).
    let existing: Stop?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editorPhotoStore) private var photoStore
    @State private var draft: Stop
    @State private var showPlaceSearch = false
    @State private var costText = ""
    @State private var minutesText = ""

    init(journey: Journey, stop: Stop?) {
        self.journey = journey
        self.existing = stop
        _draft = State(initialValue: stop ?? Stop(placeName: ""))
    }

    private var isNew: Bool { existing == nil }

    var body: some View {
        StopForm(stop: draft, journey: journey, costText: $costText, minutesText: $minutesText,
                 showPlaceSearch: $showPlaceSearch, photoStore: photoStore, canEditPhotos: !isNew)
            .navigationTitle(isNew ? "New stop" : (draft.placeName.isEmpty ? "Stop" : draft.placeName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isNew {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            JourneyEditor(context: context, photos: photoStore).addStop(draft, to: journey)
                            dismiss()
                        }
                        .disabled(!EditorLogic.canSave(placeName: draft.placeName))
                        .accessibilityIdentifier("saveStop")
                    }
                }
            }
            .sheet(isPresented: $showPlaceSearch) { PlaceSearchSheet(stop: draft) }
            .onAppear {
                costText = draft.costAmount.map { "\($0)" } ?? ""
                minutesText = draft.timeSpentMinutes.map(String.init) ?? ""
            }
    }
}

private struct StopForm: View {
    @Bindable var stop: Stop
    let journey: Journey
    @Binding var costText: String
    @Binding var minutesText: String
    @Binding var showPlaceSearch: Bool
    let photoStore: any PhotoStoring
    let canEditPhotos: Bool

    var body: some View {
        Form {
            placeSection
            storySection
            locationSection
            timeSection
            photosSection
            detailsSection
            reviewSection
            costSection
        }
        .foregroundStyle(KraftColor.ink)
        .calmForm()
    }

    // MARK: Sections

    private var placeSection: some View {
        Section {
            TextField("Place name (required)", text: $stop.placeName)
                .font(KraftFont.stopName(28, scaled: true))
                .accessibilityIdentifier("placeName")
            Picker("Category", selection: Binding(get: { stop.category }, set: { stop.category = $0 })) {
                Text("None").tag(StopCategory?.none)
                ForEach(StopCategory.allCases, id: \.self) { c in
                    Label { Text(EditorLogic.categoryName(c)) } icon: {
                        CategoryIcon(category: EditorLogic.kraft(c), size: 20)
                    }.tag(StopCategory?.some(c))
                }
            }
        } header: { Text("Place") }
    }

    private var storySection: some View {
        Section {
            TextEditor(text: Binding(
                get: { stop.story },
                set: { stop.story = EditorLogic.limitedStory($0) }))
                .font(KraftFont.body(16, scaled: true))
                .lineSpacing(KraftFont.bodyLineSpacing)
                .frame(minHeight: 140)
                .accessibilityIdentifier("storyEditor")
        } header: { Text("Story") } footer: {
            HStack { Spacer(); WordCounter(text: stop.story) }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            if let addr = stop.address, !addr.isEmpty {
                Text(addr)
            }
            if let lat = stop.latitude, let lon = stop.longitude {
                Text(String(format: "%.4f, %.4f", lat, lon))
                    .font(.footnote).foregroundStyle(KraftColor.inkSoft)
            } else if stop.address?.isEmpty != false {
                Text("No location yet").foregroundStyle(KraftColor.inkSoft)
            }
            Button { showPlaceSearch = true } label: { Label("Find this place", systemImage: "magnifyingglass") }
                .accessibilityIdentifier("findPlace")
        }
    }

    private var timeSection: some View {
        Section("Time") {
            Toggle("Arrival time", isOn: Binding(
                get: { stop.arrivalTime != nil },
                set: { stop.arrivalTime = $0 ? (stop.arrivalTime ?? journey.date) : nil }))
            if stop.arrivalTime != nil {
                DatePicker("Arrived", selection: Binding(
                    get: { stop.arrivalTime ?? journey.date }, set: { stop.arrivalTime = $0 }),
                    displayedComponents: [.hourAndMinute])
                    .environment(\.timeZone, TimeZone(identifier: journey.timeZoneID) ?? .current)
            }
            HStack {
                Text("Time spent")
                TextField("min", text: $minutesText)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .onChange(of: minutesText) { _, v in stop.timeSpentMinutes = EditorLogic.parseMinutes(v) }
                Text("min").foregroundStyle(KraftColor.inkSoft)
                Stepper("Time spent", value: Binding(
                    get: { stop.timeSpentMinutes ?? 0 },
                    set: { stop.timeSpentMinutes = max(0, $0); minutesText = String(max(0, $0)) }),
                    in: 0...1440, step: 5)
                    .labelsHidden()
            }
        }
    }

    private var photosSection: some View {
        Section {
            PhotoGridEditor(stop: stop, store: photoStore)
            Button { } label: { Label("Add photos to this stop", systemImage: "photo.badge.plus") }
                .disabled(true)
            // TODO(B3): importing photos into an existing stop is owned by the Capture flow.
        } header: { Text("Photos (\(stop.photos.count) of \(PhotoLimits.maxPerStop))") } footer: {
            if !canEditPhotos { Text("Save the stop first to manage photos.") }
        }
    }

    private var detailsSection: some View {
        Section("Highlight") {
            TextField("One short line", text: Binding(
                get: { stop.highlight ?? "" },
                set: { let t = EditorLogic.limitedChars($0, max: EditorLogic.highlightMaxChars)
                       stop.highlight = t.isEmpty ? nil : t }))
        }
    }

    private var reviewSection: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        stop.rating = (stop.rating == i) ? nil : i
                    } label: {
                        Image(systemName: (stop.rating ?? 0) >= i ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(KraftColor.stampTeal)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                    .accessibilityAddTraits((stop.rating ?? 0) >= i ? .isSelected : [])
                }
                Spacer()
            }
            TextField("Short review", text: Binding(
                get: { stop.review ?? "" },
                set: { let t = EditorLogic.limitedChars($0, max: EditorLogic.reviewMaxChars)
                       stop.review = t.isEmpty ? nil : t }))
        } header: { Text("Rating and review") }
    }

    private var costSection: some View {
        Section("Cost") {
            HStack {
                Text(EditorLogic.symbol(for: stop.costCurrency ?? EditorLogic.defaultCurrency))
                TextField("Amount", text: $costText)
                    .keyboardType(.decimalPad)
                    .onChange(of: costText) { _, v in
                        let a = EditorLogic.parseAmount(v)
                        stop.costAmount = a
                        if a != nil, stop.costCurrency == nil { stop.costCurrency = EditorLogic.defaultCurrency }
                    }
                Picker("Currency", selection: Binding(
                    get: { stop.costCurrency ?? EditorLogic.defaultCurrency },
                    set: { stop.costCurrency = $0 })) {
                    ForEach(EditorLogic.currencies, id: \.code) { Text($0.code).tag($0.code) }
                }
                .labelsHidden()
            }
        }
    }
}

// MARK: Photos

private struct PhotoGridEditor: View {
    @Bindable var stop: Stop
    let store: any PhotoStoring

    var body: some View {
        let photos = stop.orderedPhotos
        if photos.isEmpty {
            Text("No photos yet").foregroundStyle(KraftColor.inkSoft)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 10)], spacing: 10) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { idx, photo in
                    PhotoTile(photo: photo, store: store, isHero: stop.hero === photo)
                        .contextMenu {
                            Button("Make hero", systemImage: "star") { stop.setHero(photo) }
                                .disabled(stop.hero === photo)
                            Button("Move earlier", systemImage: "arrow.left") { move(photos, idx, -1) }
                                .disabled(idx == 0)
                            Button("Move later", systemImage: "arrow.right") { move(photos, idx, 1) }
                                .disabled(idx == photos.count - 1)
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                store.removePhoto(photo, from: stop)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Button { store.removePhoto(photo, from: stop) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(KraftColor.polaroidWhite, KraftColor.ink.opacity(0.7))
                                    .font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .padding(2)
                            .accessibilityLabel("Remove photo")
                        }
                }
            }
            Text("Touch and hold a photo to set the hero or reorder.")
                .font(.footnote).foregroundStyle(KraftColor.inkSoft)
        }
    }

    private func move(_ photos: [StopPhoto], _ idx: Int, _ delta: Int) {
        var list = photos
        list.swapAt(idx, idx + delta)
        for (i, p) in list.enumerated() { p.orderIndex = i }
    }
}

private struct PhotoTile: View {
    let photo: StopPhoto
    let store: any PhotoStoring
    let isHero: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                KraftColor.paperDeep
                    .overlay(Image(systemName: "photo").foregroundStyle(KraftColor.kraftDark))
            }
            if isHero {
                Label("Hero", systemImage: "star.fill")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(KraftColor.highlight, in: Capsule())
                    .foregroundStyle(KraftColor.ink)
                    .padding(4)
            }
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(KraftColor.paperEdge, lineWidth: 0.5))
        .accessibilityLabel(isHero ? "Hero photo" : "Photo")
    }

    private var image: UIImage? {
        guard !photo.thumbRelativePath.isEmpty, !photo.thumbRelativePath.hasPrefix("sample:") else { return nil }
        return UIImage(contentsOfFile: store.url(for: photo.thumbRelativePath).path)
    }
}

// MARK: Place search

struct PlaceSearchSheet: View {
    @Bindable var stop: Stop
    @Environment(\.servicePlaceLookup) private var lookup
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PlaceCandidate] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty {
                    Text(searching ? "Searching..." : (searched ? "No places found." : "Type a place name to search."))
                        .foregroundStyle(KraftColor.inkSoft)
                }
                ForEach(results) { c in
                    Button { apply(c) } label: {
                        VStack(alignment: .leading) {
                            Text(c.name).foregroundStyle(KraftColor.ink)
                            if let a = c.address { Text(a).font(.footnote).foregroundStyle(KraftColor.inkSoft) }
                        }
                    }
                }
            }
            .calmForm()
            .navigationTitle("Find this place")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .onSubmit(of: .search) { Task { await run() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { query = stop.placeName; if !query.isEmpty { await run() } }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        results = await lookup.search(q, nearLatitude: stop.latitude, nearLongitude: stop.longitude)
        searching = false
        searched = true
    }

    private func apply(_ c: PlaceCandidate) {
        if stop.placeName.trimmingCharacters(in: .whitespaces).isEmpty { stop.placeName = c.name }
        stop.address = c.address
        stop.latitude = c.latitude
        stop.longitude = c.longitude
        if let city = c.city { stop.cityHint = city }
        dismiss()
    }
}

/// Route-driven wrapper (resolves persistent ids).
struct StopEditorRouteView: View {
    let journeyID: PersistentIdentifier
    let stopID: PersistentIdentifier?
    @Environment(\.modelContext) private var context

    var body: some View {
        if let journey = context.model(for: journeyID) as? Journey {
            StopEditorView(journey: journey, stop: stopID.flatMap { context.model(for: $0) as? Stop })
        } else {
            ContentUnavailableView("Story not found", systemImage: "book.closed")
        }
    }
}

#Preview("Stop editor") {
    let container = AppContainer.make(inMemory: true)
    let journey = SampleData.mumbai(in: container.mainContext)
    return NavigationStack { StopEditorView(journey: journey, stop: journey.orderedStops[0]) }
        .modelContainer(container)
}

#Preview("New stop") {
    let container = AppContainer.make(inMemory: true)
    let journey = SampleData.mumbai(in: container.mainContext)
    return NavigationStack { StopEditorView(journey: journey, stop: nil) }
        .modelContainer(container)
}
