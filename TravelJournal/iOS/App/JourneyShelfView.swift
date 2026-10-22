import SwiftUI
import SwiftData

struct JourneyShelfView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openJourney) private var openJourney
    @Environment(\.newJourneyRequests) private var newJourneyRequests
    @Query(sort: \Journey.date, order: .reverse) private var journeys: [Journey]

    @State private var path: [AppRoute] = []
    @State private var showCreate = false
    @State private var showPlaces = false
    @State private var pendingDelete: Journey?
    @State private var query = ""
    /// Value snapshots for the library screens; rebuilt when the data or the navigation stack changes, not per render.
    @State private var stories: [LibraryStory] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                KraftColor.paper.ignoresSafeArea()
                if journeys.isEmpty { emptyState } else { shelf }
            }
            .navigationTitle("My Stories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: { Label("New story", systemImage: "plus") }
                        .accessibilityIdentifier("newStoryToolbar")
                }
                #if DEBUG
                ToolbarItem(placement: .secondaryAction) {
                    Button("Add sample journey", systemImage: "wand.and.stars") {
                        SampleData.mumbai(in: context)
                    }
                    .accessibilityIdentifier("addSampleJourney")
                }
                #endif
            }
            .appDestinations()
            #if DEBUG
            .task {
                // Debug launch args: -openSample (journey detail), -openSampleStop (stop editor)
                // -seedSample (one story), -seedLibrary N (N stories across countries)
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-seedSample"), journeys.isEmpty { SampleData.mumbai(in: context) }
                SampleData.seedFromLaunchArguments(in: context)
                if let i = args.firstIndex(of: "-openRack") {
                    // -openRack N: India cover rack starting on its Nth story (debug aid)
                    let all = journeys.libraryStories
                    let scope = StoryScope(kind: .country("India"), title: "India")
                    let inScope = LibraryIndex.stories(in: scope, from: all)
                    let n = args.indices.contains(i + 1) ? Int(args[i + 1]) ?? 0 : 0
                    if inScope.indices.contains(n) { path = [.coverRack(scope: scope, startStoryID: inScope[n].id)] }
                    return
                }
                guard args.contains("-openSample") || args.contains("-openSampleStop") || args.contains("-openSampleStory") else { return }
                let j = journeys.first ?? SampleData.mumbai(in: context)
                path = [.journeyDetail(j.persistentModelID)]
                if args.contains("-openSampleStory") { path.append(.story(j.persistentModelID)) }
                if args.contains("-openSampleStop"), let s = j.orderedStops.first {
                    path.append(.stopEditor(journey: j.persistentModelID, stop: s.persistentModelID))
                }
            }
            #endif
            .onAppear(perform: refreshStories)
            .onChange(of: journeys) { refreshStories() }
            .onChange(of: path) { refreshStories() }
            .onAppear(perform: consumeNewJourneyRequest)
            .onChange(of: newJourneyRequests?.pending) { consumeNewJourneyRequest() }
            .sheet(isPresented: $showPlaces) {
                PlacesBrowserView(stories: stories) { scope in
                    showPlaces = false
                    if let first = LibraryIndex.stories(in: scope, from: stories).first {
                        path.append(.coverRack(scope: scope, startStoryID: first.id))
                    }
                }
                .preferredColorScheme(.light)
            }
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
                    JourneyEditor(context: context, photos: ModelPhotoStore()).deleteJourney(journey)
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { _ in
                Text("The story and all its stops will be removed. This can't be undone.")
            }
        }
        .measuringStatusBarInset()   // above the stack, so the story viewer gets the constant status-bar height
        .tint(KraftColor.route)
    }

    private func refreshStories() { stories = journeys.libraryStories }

    private func open(_ journey: Journey) {
        if let openJourney { openJourney(journey) } else { path.append(.journeyDetail(journey.persistentModelID)) }
    }

    private func consumeNewJourneyRequest() {
        guard let requests = newJourneyRequests, requests.pending else { return }
        requests.pending = false
        showCreate = true
    }

    private func journey(for story: LibraryStory) -> Journey? { journeys.first { $0.id == story.id } }

    private var shelf: some View {
        LibraryBookcaseView(
            stories: stories,
            query: $query,
            actions: LibraryActions(
                openStory: { story in
                    if let j = journey(for: story) { open(j) }
                },
                openRack: { scope, start in path.append(.coverRack(scope: scope, startStoryID: start)) },
                openPlaces: { showPlaces = true },
                requestDelete: { story in pendingDelete = journey(for: story) }
            )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 56)).foregroundStyle(KraftColor.kraftDark)
                .accessibilityHidden(true)
            Text("No stories yet").font(.title3.weight(.semibold)).foregroundStyle(KraftColor.ink)
            Text("Turn a trip into a scrapbook you can share.")
                .font(.body).foregroundStyle(KraftColor.inkSoft)
                .multilineTextAlignment(.center)
            Button { showCreate = true } label: {
                Label("New story", systemImage: "plus").padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(KraftColor.route)
            .controlSize(.large)
            .accessibilityIdentifier("newStoryEmpty")
            #if DEBUG
            Button("Add sample journey") { SampleData.mumbai(in: context) }
                .font(.footnote)
                .accessibilityIdentifier("addSampleJourneyEmpty")
            #endif
        }
        .padding(32)
    }
}

/// Book-cover card: the journey's cover photo when a file exists, otherwise a kraft placeholder.
struct JourneyCoverCard: View {
    let journey: Journey

    @Environment(\.displayScale) private var displayScale

    private var coverImage: CGImage? {
        StoredPhotos.image(photo: journey.coverPhoto,
                           maxPixel: ImageDecoding.maxPixel(forPoints: 240, scale: displayScale))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                KraftColor.kraft
                if let cover = coverImage {
                    GeometryReader { geo in
                        Image(texture: cover, scale: displayScale).resizable().scaledToFill()   // card is one labelled element
                            .frame(width: geo.size.width, height: geo.size.height).clipped()
                    }
                    .overlay(LinearGradient(colors: [.clear, KraftColor.ink.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                }
                VStack(spacing: 6) {
                    Text(journey.title)
                        .font(KraftFont.stopName(30))
                        .foregroundStyle(coverImage == nil ? KraftColor.ink : KraftColor.paper)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                    Rectangle().fill(KraftColor.kraftDark.opacity(0.5)).frame(width: 40, height: 1)
                }
                .padding(14)
                .frame(maxHeight: .infinity, alignment: coverImage == nil ? .center : .bottom)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4,
                                              bottomTrailingRadius: 10, topTrailingRadius: 10))
            .overlay(alignment: .leading) {
                Rectangle().fill(KraftColor.kraftDark.opacity(0.35)).frame(width: 6)
            }
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 3)

            VStack(spacing: 2) {
                Text(journey.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.footnote).foregroundStyle(KraftColor.inkSoft)
                if let city = journey.city, !city.isEmpty {
                    Text(city).font(.footnote.weight(.medium)).foregroundStyle(KraftColor.ink)
                }
            }
            .padding(.top, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the story")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var s = journey.title + ", " + journey.date.formatted(date: .long, time: .omitted)
        if let c = journey.city, !c.isEmpty { s += ", " + c }
        return s
    }
}

#Preview("Shelf with sample") {
    let container = AppContainer.make(inMemory: true)
    SampleData.mumbai(in: container.mainContext)
    return JourneyShelfView().modelContainer(container)
}

#Preview("Shelf empty") {
    JourneyShelfView().modelContainer(AppContainer.make(inMemory: true))
}
