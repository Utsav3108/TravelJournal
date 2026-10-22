import SwiftUI

/// The library home: a walnut bookcase of spines grouped on shelves, with a pinned search field.
struct LibraryBookcaseView: View {
    let stories: [LibraryStory]
    @Binding var query: String
    let actions: LibraryActions
    private let shelfProvider: ([LibraryStory], String) -> [LibraryShelf]

    @State private var shelves: [LibraryShelf]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(stories: [LibraryStory], query: Binding<String>, actions: LibraryActions) {
        self.init(stories: stories, query: query, actions: actions,
                  shelfProvider: { LibraryIndex.shelves(from: $0, query: $1) })
    }

    /// Internal seam so previews can supply shelves directly.
    init(stories: [LibraryStory], query: Binding<String>, actions: LibraryActions,
         shelfProvider: @escaping ([LibraryStory], String) -> [LibraryShelf]) {
        self.stories = stories
        self._query = query
        self.actions = actions
        self.shelfProvider = shelfProvider
        self._shelves = State(initialValue: shelfProvider(stories, query.wrappedValue))
    }

    private var searching: Bool { !query.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            BookcaseSearchField(query: $query)
            ScrollView {
                content
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(KraftColor.paper.ignoresSafeArea())
        .onChange(of: stories) { _, _ in refresh() }
        .onChange(of: query) { _, _ in refresh() }
    }

    private func refresh() {
        shelves = shelfProvider(stories, query)
    }

    @ViewBuilder private var content: some View {
        if shelves.isEmpty && searching {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(KraftColor.inkSoft)
                Text("No stories match")
                    .font(.custom(KraftFontName.lora, size: 18, relativeTo: .headline))
                    .foregroundStyle(KraftColor.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 0) {
                cap
                LazyVStack(spacing: 0) {
                    if shelves.isEmpty {
                        ForEach(0..<3, id: \.self) { i in
                            emptyShelf(i)
                        }
                    } else {
                        ForEach(shelves) { shelf in
                            shelfView(shelf)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(BookcasePalette.walnut)
                .overlay(alignment: .leading) { sideRail }
                .overlay(alignment: .trailing) { sideRail }
                Rectangle().fill(BookcasePalette.walnutDark).frame(height: 10)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
    }

    private var sideRail: some View {
        LinearGradient(colors: [BookcasePalette.walnutLight, BookcasePalette.walnutDark], startPoint: .leading, endPoint: .trailing)
            .frame(width: 12)
    }

    private var cap: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [BookcasePalette.walnutLight, BookcasePalette.walnut], startPoint: .top, endPoint: .bottom)
                .frame(height: 20)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
            BookcaseGlobeButton(action: actions.openPlaces)
                .padding(.trailing, 24)
                .padding(.bottom, 17)
        }
        .frame(height: 74)
    }

    private func emptyShelf(_ i: Int) -> some View {
        VStack(spacing: 0) {
            BookcaseGrain(seed: 100 + i).frame(height: 130)
            BookcasePlank()
        }
    }

    private func shelfView(_ shelf: LibraryShelf) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                BookcaseGrain(seed: bookcaseStableSeed(shelf.id.utf8))
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        BookcaseLabelPlate(title: shelf.title, count: shelf.stories.count) {
                            if let first = shelf.stories.first { actions.openRack(shelf.scope, first.id) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 8)
                    spineRow(shelf)
                }
            }
            BookcasePlank()
        }
    }

    private func spineRow(_ shelf: LibraryShelf) -> some View {
        GeometryReader { geo in
            let scale = rowScale(shelf, available: geo.size.width - 16)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(shelf.slots.enumerated()), id: \.offset) { _, slot in
                    switch slot {
                    case .spine(let story):
                        BookcaseSpine(story: story, colorIndex: shelf.colorIndex, scale: scale,
                                      highlighted: searching,
                                      onOpen: { actions.openStory(story) },
                                      onDelete: { actions.requestDelete(story) })
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: searching)
                    case .more(let count, let idx):
                        BookcaseMoreTile(count: count, shelfTitle: shelf.title, scale: scale) {
                            if shelf.stories.indices.contains(idx) { actions.openRack(shelf.scope, shelf.stories[idx].id) }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
        .frame(height: 146)
    }

    private func rowScale(_ shelf: LibraryShelf, available: CGFloat) -> CGFloat {
        var total: CGFloat = 0
        for slot in shelf.slots {
            switch slot {
            case .spine(let s): total += BookcasePalette.thickness(weight: s.weight)
            case .more: total += 34
            }
        }
        total += CGFloat(max(0, shelf.slots.count - 1)) * 2
        guard total > 0, available > 0 else { return 1 }
        return min(1, available / total)
    }
}

// MARK: - Previews

/// Preview-only grouping by country (up to 10 slots with a "+N more" tile) so layouts show
/// even while `LibraryIndex` is a stub.
private func bookcasePreviewShelves(_ stories: [LibraryStory], _ query: String) -> [LibraryShelf] {
    let q = query.lowercased()
    let filtered = q.isEmpty ? stories : stories.filter {
        $0.title.lowercased().contains(q) || ($0.city ?? "").lowercased().contains(q)
    }
    var order: [String] = []
    var groups: [String: [LibraryStory]] = [:]
    for s in filtered {
        let key = s.country ?? "Other"
        if groups[key] == nil { order.append(key) }
        groups[key, default: []].append(s)
    }
    return order.map { key in
        let list = groups[key] ?? []
        var slots: [LibraryShelfSlot] = []
        if list.count <= 10 {
            slots = list.map { .spine($0) }
        } else {
            slots = list.prefix(9).map { .spine($0) }
            slots.append(.more(count: list.count - 9, firstHiddenIndex: 9))
        }
        return LibraryShelf(id: "country:\(key)", title: key,
                            scope: StoryScope(kind: key == "Other" ? .other : .country(key), title: key, query: query),
                            stories: list, slots: slots,
                            colorIndex: abs(bookcaseStableSeed(key.utf8)) % BookcasePalette.colors.count)
    }
}

private struct BookcasePreviewHost: View {
    let stories: [LibraryStory]
    @State var query: String
    init(count: Int, singleCountry: Bool = false, noCountryEvery: Int? = nil, query: String = "") {
        stories = LibraryFixtures.stories(count: count, singleCountry: singleCountry, noCountryEvery: noCountryEvery)
        _query = State(initialValue: query)
    }
    var body: some View {
        NavigationStack {
            LibraryBookcaseView(stories: stories, query: $query,
                                actions: LibraryActions(openStory: { _ in }, openRack: { _, _ in },
                                                        openPlaces: {}, requestDelete: { _ in }),
                                shelfProvider: bookcasePreviewShelves)
                .navigationTitle("Library")
                .inlineNavigationTitle()
        }
    }
}

#Preview("0") { BookcasePreviewHost(count: 0) }
#Preview("1") { BookcasePreviewHost(count: 1) }
#Preview("6") { BookcasePreviewHost(count: 6) }
#Preview("7") { BookcasePreviewHost(count: 7) }
#Preview("10") { BookcasePreviewHost(count: 10) }
#Preview("11") { BookcasePreviewHost(count: 11) }
#Preview("19") { BookcasePreviewHost(count: 19) }
#Preview("60") { BookcasePreviewHost(count: 60) }
#Preview("Single country") { BookcasePreviewHost(count: 30, singleCountry: true) }
#Preview("No country every 4") { BookcasePreviewHost(count: 19, noCountryEvery: 4) }
#Preview("Query") { BookcasePreviewHost(count: 19, query: "Mumbai") }
