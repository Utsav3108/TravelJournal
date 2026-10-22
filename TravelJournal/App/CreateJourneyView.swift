import SwiftUI
import SwiftData

/// Calm editor-style sheet: paper background, ink text, system controls (no scrapbook look).
struct CreateJourneyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var onCreated: (Journey) -> Void = { _ in }

    @State private var title = ""
    @State private var date = Date()
    @State private var city = ""
    @State private var country = ""

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityLabel("Story title, required")
                        .accessibilityIdentifier("journeyTitleField")
                        .submitLabel(.done)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .accessibilityIdentifier("journeyDatePicker")
                    TextField("City (optional)", text: $city)
                        .accessibilityLabel("City, optional")
                        .accessibilityIdentifier("journeyCityField")
                    TextField("Country (optional)", text: $country)
                        .accessibilityLabel("Country, optional")
                        .accessibilityIdentifier("journeyCountryField")
                } footer: {
                    Text("A title is required.").foregroundStyle(KraftColor.inkSoft)
                }
                .listRowBackground(KraftColor.paperDeep.opacity(0.6))
            }
            .scrollContentBackground(.hidden)
            .background(KraftColor.paper.ignoresSafeArea())
            .foregroundStyle(KraftColor.ink)
            .navigationTitle("New story")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedTitle.isEmpty)
                        .accessibilityIdentifier("saveJourneyButton")
                }
            }
        }
        .tint(KraftColor.route)
        .preferredColorScheme(.light)
    }

    private func save() {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let journey = Journey(title: trimmedTitle,
                              date: date,
                              city: trimmedCity.isEmpty ? nil : trimmedCity,
                              country: trimmedCountry.isEmpty ? nil : trimmedCountry)
        context.insert(journey)
        try? context.save()
        dismiss()
        onCreated(journey)
    }
}

#Preview("Create") {
    CreateJourneyView().modelContainer(AppContainer.make(inMemory: true))
}
