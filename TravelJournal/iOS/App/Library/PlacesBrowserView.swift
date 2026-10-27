import SwiftUI

/// Presented in a sheet by the host. Calls `onSelect` with a country or city scope, then the host dismisses and pushes the rack.
struct PlacesBrowserView: View {
    let stories: [LibraryStory]
    let onSelect: (StoryScope) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var countries: [LibraryCountry] = []

    var body: some View {
        NavigationStack {
            Group {
                if countries.isEmpty {
                    emptyState
                } else {
                    PlacesCountryList(countries: countries, onSelect: onSelect)
                }
            }
            .background(KraftColor.paper.ignoresSafeArea())
            .navigationTitle("Places")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(KraftColor.route)
        .preferredColorScheme(.light)
        .onAppear { countries = LibraryIndex.countries(from: stories) }
        .onChange(of: stories) { _, new in countries = LibraryIndex.countries(from: new) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 40))
                .foregroundStyle(KraftColor.route)
                .accessibilityHidden(true)
            Text("No places yet. Add a country to a story to see it here.")
                .font(.body)
                .foregroundStyle(KraftColor.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct PlacesCountryList: View {
    let countries: [LibraryCountry]
    let onSelect: (StoryScope) -> Void

    var body: some View {
        List(countries) { country in
            NavigationLink {
                CityListView(country: country, onSelect: onSelect)
            } label: {
                PlaceRow(name: country.name, count: country.count)
            }
            .listRowBackground(KraftColor.paper)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct CityListView: View {
    let country: LibraryCountry
    let onSelect: (StoryScope) -> Void

    var body: some View {
        List {
            Button {
                onSelect(StoryScope(kind: .country(country.name), title: country.name))
            } label: {
                PlaceRow(name: "All of \(country.name)", count: country.count, emphasized: true)
            }
            .listRowBackground(KraftColor.paper)
            ForEach(country.cities) { city in
                Button {
                    onSelect(StoryScope(kind: .city(city.name), title: city.name))
                } label: {
                    PlaceRow(name: city.name, count: city.count)
                }
                .listRowBackground(KraftColor.paper)
            }
        }
        .scrollContentBackground(.hidden)
        .background(KraftColor.paper.ignoresSafeArea())
        .navigationTitle(country.name)
        .inlineNavigationTitle()
    }
}

private struct PlaceRow: View {
    let name: String
    let count: Int
    var emphasized = false

    var body: some View {
        HStack {
            Text(name)
                .font(emphasized ? .body.weight(.semibold) : .body)
                .foregroundStyle(emphasized ? KraftColor.route : KraftColor.ink)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(KraftColor.inkSoft)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "story" : "stories")")
    }
}

#if DEBUG
private func previewCountries(_ stories: [LibraryStory]) -> [LibraryCountry] {
    Dictionary(grouping: stories.filter { $0.country != nil }, by: { $0.country! })
        .map { name, list in
            let cities = Dictionary(grouping: list.compactMap(\.city), by: { $0 })
                .map { LibraryCity(name: $0.key, count: $0.value.count) }
                .sorted { $0.name < $1.name }
            return LibraryCountry(name: name, count: list.count, cities: cities)
        }
        .sorted { $0.name < $1.name }
}

private struct PlacesPreviewHost: View {
    let countries: [LibraryCountry]
    var body: some View {
        NavigationStack {
            PlacesCountryList(countries: countries, onSelect: { _ in })
                .background(KraftColor.paper)
                .navigationTitle("Places")
                .inlineNavigationTitle()
        }
        .tint(KraftColor.route)
    }
}

#Preview("Several countries") {
    PlacesPreviewHost(countries: previewCountries(LibraryFixtures.stories(count: 30)))
}
#Preview("One country") {
    PlacesPreviewHost(countries: previewCountries(LibraryFixtures.stories(count: 10, singleCountry: true)))
}
#Preview("Empty") { PlacesBrowserView(stories: [], onSelect: { _ in }) }
#endif
