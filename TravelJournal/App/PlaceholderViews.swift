import SwiftUI
import SwiftData

struct JourneyDetailPlaceholderView: View {
    let journeyID: PersistentIdentifier
    @Environment(\.modelContext) private var context

    var body: some View {
        let journey = context.model(for: journeyID) as? Journey
        ZStack {
            KraftColor.paper.ignoresSafeArea()
            VStack(spacing: 12) {
                Text(journey?.title ?? "Story")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(KraftColor.ink)
                Text("\(journey?.stops.count ?? 0) stops")
                    .foregroundStyle(KraftColor.inkSoft)
                Text("Story detail arrives in a later phase.")
                    .font(.footnote).foregroundStyle(KraftColor.inkSoft)
                NavigationLink(value: AppRoute.stopEditor(journey: journeyID, stop: nil)) {
                    Label("Add a stop", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(KraftColor.route)
            }
            .multilineTextAlignment(.center)
            .padding()
        }
        .navigationTitle(journey?.title ?? "Story")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StopEditorPlaceholderView: View {
    let journeyID: PersistentIdentifier

    var body: some View {
        ZStack {
            KraftColor.paper.ignoresSafeArea()
            Text("Stop editor arrives in a later phase.")
                .foregroundStyle(KraftColor.inkSoft)
                .multilineTextAlignment(.center)
                .padding()
        }
        .navigationTitle("New stop")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Detail") {
    let container = AppContainer.make(inMemory: true)
    let journey = SampleData.mumbai(in: container.mainContext)
    return NavigationStack { JourneyDetailPlaceholderView(journeyID: journey.persistentModelID) }
        .modelContainer(container)
}

#Preview("Stop editor") {
    let container = AppContainer.make(inMemory: true)
    let journey = SampleData.mumbai(in: container.mainContext)
    return NavigationStack { StopEditorPlaceholderView(journeyID: journey.persistentModelID) }
        .modelContainer(container)
}
