import SwiftUI
import SwiftData

struct JourneyShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Journey.date, order: .reverse) private var journeys: [Journey]

    @State private var path: [AppRoute] = []
    @State private var showCreate = false
    @State private var pendingDelete: Journey?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

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
            .sheet(isPresented: $showCreate) {
                CreateJourneyView { journey in
                    path.append(.journeyDetail(journey.persistentModelID))
                }
            }
            .confirmationDialog(
                "Delete this story?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { journey in
                Button("Delete \"\(journey.title)\"", role: .destructive) {
                    context.delete(journey)
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { _ in
                Text("The story and all its stops will be removed. This can't be undone.")
            }
        }
        .tint(KraftColor.route)
    }

    private var shelf: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(journeys) { journey in
                    NavigationLink(value: AppRoute.journeyDetail(journey.persistentModelID)) {
                        JourneyCoverCard(journey: journey)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { pendingDelete = journey } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(20)
        }
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

/// Book-cover card. Cover photo hook arrives with the photo pipeline; kraft placeholder for now.
struct JourneyCoverCard: View {
    let journey: Journey

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                KraftColor.kraft
                VStack(spacing: 6) {
                    Text(journey.title)
                        .font(KraftFont.stopName(30))
                        .foregroundStyle(KraftColor.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                    Rectangle().fill(KraftColor.kraftDark.opacity(0.5)).frame(width: 40, height: 1)
                }
                .padding(14)
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
