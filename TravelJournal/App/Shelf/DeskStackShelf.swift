import SwiftUI

/// PLACEHOLDER: replaced by the real desk stack shelf look.
struct DeskStackShelfView: View {
    let context: ShelfStyleContext
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

    var body: some View {
        ZStack {
            KraftColor.paper.ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(context.journeys) { journey in
                        Button { context.open(journey) } label: { JourneyCoverCard(journey: journey) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { context.requestDelete(journey) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(20)
            }
        }
    }
}
