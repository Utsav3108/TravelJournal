import SwiftUI

/// Cover Rack: covers face out on a wooden plank in a cover-flow carousel.
/// `stories` is the FULL library; the view narrows it with `LibraryIndex.stories(in:from:)` and its city chips.
struct LibraryCoverRackView: View {
    let scope: StoryScope
    let stories: [LibraryStory]
    let startStoryID: UUID
    let openStory: (LibraryStory) -> Void

    @State private var scoped: [LibraryStory]
    @State private var cities: [LibraryCity]

    init(scope: StoryScope, stories: [LibraryStory], startStoryID: UUID, openStory: @escaping (LibraryStory) -> Void) {
        self.scope = scope
        self.stories = stories
        self.startStoryID = startStoryID
        self.openStory = openStory
        let s = LibraryIndex.stories(in: scope, from: stories)
        _scoped = State(initialValue: s)
        _cities = State(initialValue: LibraryIndex.cities(in: s))
    }

    var body: some View {
        CoverRackContent(stories: scoped, cities: cities, startStoryID: startStoryID, openStory: openStory)
            .onChange(of: scope) { _, _ in refresh() }
            .onChange(of: stories) { _, _ in refresh() }
    }

    private func refresh() {
        let s = LibraryIndex.stories(in: scope, from: stories)
        scoped = s
        cities = LibraryIndex.cities(in: s)
    }
}

/// Renders already-narrowed stories (previews feed it directly).
struct CoverRackContent: View {
    let stories: [LibraryStory]
    let cities: [LibraryCity]
    let startStoryID: UUID
    let openStory: (LibraryStory) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var city: String?
    @State private var selectedID: UUID?
    @State private var displayed: [LibraryStory]

    init(stories: [LibraryStory], cities: [LibraryCity], startStoryID: UUID, openStory: @escaping (LibraryStory) -> Void) {
        self.stories = stories
        self.cities = cities
        self.startStoryID = startStoryID
        self.openStory = openStory
        _displayed = State(initialValue: stories)
        _selectedID = State(initialValue: stories.contains { $0.id == startStoryID } ? startStoryID : stories.first?.id)
    }

    private var currentIndex: Int {
        displayed.firstIndex { $0.id == selectedID } ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let itemW = min(geo.size.width * 0.58, 280)
            let itemH = itemW * 1.45
            ZStack {
                CoverRackLibWall().ignoresSafeArea()
                VStack(spacing: 0) {
                    if cities.count >= 2 {
                        CoverRackChips(cities: cities, total: stories.count, selection: city, select: selectCity)
                            .padding(.top, 8)
                    }
                    Spacer(minLength: 0)
                    ZStack(alignment: .top) {
                        CoverRackLibPlank().frame(height: 80).offset(y: itemH - 4)
                        carousel(width: geo.size.width, itemW: itemW, itemH: itemH)
                    }
                    .frame(height: itemH + 80, alignment: .top)
                    caption.padding(.top, 12)
                    if displayed.count > LibraryIndex.maxSlotsPerShelf { scrubber.padding(.top, 8) }
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
            }
        }
        .onChange(of: stories) { _, _ in
            if let c = city, !stories.contains(where: { $0.city == c }) { city = nil }
            applyFilter(resetToFirst: false)
        }
    }

    // MARK: Carousel

    private func carousel(width: CGFloat, itemW: CGFloat, itemH: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(displayed) { story in
                    CoverRackLibBook(story: story, width: itemW, height: itemH, tilt: !reduceMotion)
                        .frame(width: itemW, height: itemH + 60, alignment: .top)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .rotation3DEffect(.degrees(reduceMotion ? 0 : -phase.value * 42),
                                                  axis: (0, 1, 0), perspective: 0.5)
                                .scaleEffect(reduceMotion ? 1 : 1 - abs(phase.value) * 0.16, anchor: .bottom)
                                .opacity(1 - abs(phase.value) * 0.28)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { tap(story) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityText(story))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { openStory(story) }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, max((width - itemW) / 2, 0), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedID, anchor: .center)
        .scrollDisabled(displayed.count <= 1)
        .frame(height: itemH + 60)
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    // MARK: Caption and scrubber

    @ViewBuilder
    private var caption: some View {
        if displayed.indices.contains(currentIndex) {
            let s = displayed[currentIndex]
            VStack(spacing: 6) {
                Text(s.title)
                    .font(.custom(KraftFontName.loraSemiBold, size: 22, relativeTo: .title3))
                    .foregroundStyle(CoverRackLibPalette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(subtitle(s))
                    .font(.custom(KraftFontName.lora, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(CoverRackLibPalette.textSoft)
                    .lineLimit(2).multilineTextAlignment(.center)
                Text("\(currentIndex + 1) of \(displayed.count)")
                    .font(.custom(KraftFontName.lora, size: 12, relativeTo: .caption))
                    .foregroundStyle(CoverRackLibPalette.textSoft)
                    .monospacedDigit()
                    .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .combine)
        }
    }

    private var scrubber: some View {
        Slider(value: Binding(get: { Double(currentIndex) },
                              set: { jump(to: Int($0.rounded())) }),
               in: 0...Double(max(displayed.count - 1, 1)), step: 1)
            .tint(CoverRackLibPalette.text)
            .padding(.horizontal, 32)
            .frame(minHeight: 44)
            .accessibilityLabel("Story position")
            .accessibilityValue("\(currentIndex + 1) of \(displayed.count)")
    }

    // MARK: Actions

    private func jump(to i: Int) {
        guard displayed.indices.contains(i), displayed[i].id != selectedID else { return }
        if reduceMotion { selectedID = displayed[i].id }
        else { withAnimation(.easeOut(duration: 0.25)) { selectedID = displayed[i].id } }
    }

    private func tap(_ story: LibraryStory) {
        if displayed.indices.contains(currentIndex), story.id == displayed[currentIndex].id {
            openStory(story)
        } else if reduceMotion {
            selectedID = story.id
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { selectedID = story.id }
        }
    }

    private func selectCity(_ name: String?) {
        city = name
        applyFilter(resetToFirst: true)
    }

    private func applyFilter(resetToFirst: Bool) {
        displayed = city.map { c in stories.filter { $0.city == c } } ?? stories
        if resetToFirst || !displayed.contains(where: { $0.id == selectedID }) {
            selectedID = displayed.first?.id
        }
    }

    private func subtitle(_ s: LibraryStory) -> String {
        if let c = s.city, !c.isEmpty { return "\(s.dateText) · \(c)" }
        return s.dateText
    }

    private func accessibilityText(_ s: LibraryStory) -> String {
        var t = s.title
        if let c = s.city, !c.isEmpty { t += ", \(c)" }
        return t + ", \(s.date.formatted(date: .long, time: .omitted))"
    }
}

// MARK: - Previews

private func coverRackPreview(_ stories: [LibraryStory], start: Int = 0) -> some View {
    var counts: [String: Int] = [:]
    for s in stories { if let c = s.city { counts[c, default: 0] += 1 } }
    let cities = counts.map { LibraryCity(name: $0.key, count: $0.value) }.sorted { $0.name < $1.name }
    return NavigationStack {
        CoverRackContent(stories: stories, cities: cities, startStoryID: stories[start].id, openStory: { _ in })
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("1 story") { coverRackPreview(LibraryFixtures.stories(count: 1, singleCountry: true)) }
#Preview("7 stories") { coverRackPreview(LibraryFixtures.stories(count: 7, singleCountry: true)) }
#Preview("19 stories") { coverRackPreview(LibraryFixtures.stories(count: 19, singleCountry: true)) }
#Preview("60 stories") { coverRackPreview(LibraryFixtures.stories(count: 60, singleCountry: true)) }
#Preview("Multi-city") { coverRackPreview(LibraryFixtures.stories(count: 12)) }
#Preview("Start in middle") { coverRackPreview(LibraryFixtures.stories(count: 19, singleCountry: true), start: 9) }
