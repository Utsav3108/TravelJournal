import SwiftUI
import SwiftData

struct StoryViewerView: View {
    let journeyID: PersistentIdentifier
    @Environment(\.modelContext) private var context

    var body: some View {
        if let journey = context.model(for: journeyID) as? Journey {
            StoryViewerContent(journey: journey)
        } else {
            ContentUnavailableView("Story not found", systemImage: "book.closed")
        }
    }
}

struct StoryViewerContent: View {
    let journey: Journey
    @Environment(\.dismiss) private var dismiss
    @Environment(\.storyImageProvider) private var imageProvider

    @State private var pages: [StoryPage] = []
    @State private var currentID: String?
    @State private var legCard: StoryLeg?
    @State private var photo: StoryPhoto?
    @State private var editTarget: PersistentIdentifier?
    @State private var export: StoryPDFExportModel
    @State private var tempReveal = false
    @State private var revealTask: Task<Void, Never>?

    init(journey: Journey) {
        self.journey = journey
        _export = State(initialValue: StoryPDFExportModel(journey: journey))
    }

    /// Constant status-bar height (measured above the navigation stack), so pages never move when the navigation bar hides or shows.
    @Environment(\.statusBarInset) private var topInset

    var body: some View {
        let barVisible = StoryViewerLogic.barVisible(pageIndex: currentIndex, tempReveal: tempReveal)
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: max(geo.size.height - topInset, 1))
            ZStack(alignment: .bottom) {
                PaperBackground().ignoresSafeArea()
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                            pageView(page, index: i, size: size)
                                .frame(width: size.width, height: size.height)
                                .id(page.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentID)
                .scrollIndicators(.hidden)
                .padding(.top, topInset)

                indicator
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(barVisible ? .visible : .hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.25), value: barVisible)
        .onChange(of: currentIndex) { old, new in
            let keep = StoryViewerLogic.revealAfterPageChange(from: old, to: new, tempReveal: tempReveal)
            if !keep { cancelReveal() }
        }
        .onDisappear { cancelReveal() }
        .pdfExportPresentations(export)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storyViewer")
        .navigationTitle(journey.title.isEmpty ? "Story" : journey.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { StoryPDFExportButton(model: export) }
            ToolbarItem(placement: .secondaryAction) {
                Button { dismiss() } label: { Label("Edit story", systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("editStory")
            }
        }
        .onAppear { rebuild() }
        .sheet(item: $legCard) { leg in
            LegCardView(leg: leg)
                .presentationDetents([.height(340), .medium])
        }
        .platformFullScreenCover(item: $photo) { p in
            FullScreenPhotoView(photo: p, provider: imageProvider) { photo = nil }
        }
        .navigationDestination(item: $editTarget) { id in
            StopEditorRouteView(journeyID: journey.persistentModelID, stopID: id)
        }
        #if DEBUG
        .task { await debugArgs() }
        #endif
    }

    private var currentIndex: Int { StoryViewerLogic.index(of: currentID, in: pages) ?? 0 }

    private var indicator: some View {
        Text(StoryViewerLogic.indicatorText(index: currentIndex, total: max(pages.count, 1)))
            .stampLabel(12)
            .foregroundStyle(KraftColor.inkSoft)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(KraftColor.paper.opacity(0.85)))
            .padding(.bottom, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(currentIndex + 1) of \(pages.count)")
            .accessibilityIdentifier("pageIndicator")
    }

    private func pageView(_ page: StoryPage, index: Int, size: CGSize) -> some View {
        ScrollView(.vertical) {
            StoryPageView(page: page, metrics: .phone(size), callbacks: callbacks,
                          entryY: StopLayout.entryY(at: index, in: pages, metrics: .phone(size)))
                .frame(width: size.width, height: size.height)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onTapGesture { if index > 0 { revealBarTemporarily() } }   // child taps (photos, pins, buttons) win
        .accessibilityElement(children: .contain)
        .accessibilityLabel(StoryViewerLogic.pageLabel(page, index: index, total: pages.count))
    }

    private var callbacks: StoryPageCallbacks {
        StoryPageCallbacks(
            onPhotoTap: { photo = $0 },
            onLegTap: { legCard = $0 },
            onEdit: { sid in
                if let s = journey.orderedStops.first(where: { $0.id.uuidString == sid }) { editTarget = s.persistentModelID }
            },
            onPinTap: { pid in
                withAnimation(.easeInOut(duration: 0.4)) { currentID = pid }
            },
            onSavePDF: { export.start() })
    }

    private func revealBarTemporarily() {
        revealTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) { tempReveal = true }
        revealTask = Task {
            try? await Task.sleep(for: .seconds(StoryViewerLogic.barRevealSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { tempReveal = false }
            revealTask = nil
        }
    }

    private func cancelReveal() {
        revealTask?.cancel()
        revealTask = nil
        if tempReveal { withAnimation(.easeInOut(duration: 0.25)) { tempReveal = false } }
    }

    private func rebuild() {
        let old = currentIndex
        let new = StoryLayout().pages(for: journey)
        let keep = StoryViewerLogic.stableCurrentID(current: currentID, oldIndex: old, in: new)
        pages = new
        currentID = keep
    }

    #if DEBUG
    private func debugArgs() async {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-openSampleStoryPage"), i + 1 < args.count, let n = Int(args[i + 1]),
           pages.indices.contains(n) {
            try? await Task.sleep(for: .milliseconds(600))   // let the pager lay out before jumping
            currentID = pages[n].id
        }
        if args.contains("-openSampleLegCard") {
            for case .stop(let m) in pages { if let l = m.outLeg { legCard = l; break } }
        }
    }
    #endif
}

// MARK: Leg card

struct LegCardView: View {
    let leg: StoryLeg
    var body: some View {
        let t = StoryViewerLogic.legCardText(leg)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let k = TransportMode.icon(forRaw: leg.modeRaw) { TransportIcon(mode: k, size: 36) }
                Text(t.title).font(KraftFont.note(28)).foregroundStyle(KraftColor.ink)
            }
            if !t.details.isEmpty {
                Text(t.details.joined(separator: " · ")).stampLabel(13).foregroundStyle(KraftColor.stampTeal)
            }
            if let s = t.story {
                Text(s).font(KraftFont.body(16)).foregroundStyle(KraftColor.ink)
            } else if let e = t.emptyNote {
                Text(e).font(KraftFont.bodyItalic(15)).foregroundStyle(KraftColor.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PaperBackground().ignoresSafeArea())
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.accessibility)
        .accessibilityIdentifier("legCard")
    }
}

// MARK: Full-screen photo

struct FullScreenPhotoView: View {
    let photo: StoryPhoto
    let provider: StoryImageProvider
    let close: () -> Void

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var dragDown: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(1 - min(Double(dragDown) / 400, 0.5)).ignoresSafeArea()
            content
                .scaleEffect(scale)
                .offset(x: offset.width, y: offset.height + dragDown)
                .gesture(zoomGesture.simultaneously(with: dragGesture))
                .onTapGesture(count: 2) {
                    withAnimation(.spring) {
                        if scale > 1 { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero } else { scale = 2.5; baseScale = 2.5 }
                    }
                }
                .onTapGesture { if scale <= 1 { close() } }
            Button(action: close) {
                Image(systemName: "xmark.circle.fill").font(.title).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5)).padding()
            }
            .accessibilityLabel("Close photo")
        }
        .accessibilityIdentifier("photoFullScreen")
    }

    @ViewBuilder private var content: some View {
        if let cg = provider.image(for: photo, preferThumbnail: false,
                                   maxPixel: ImageDecoding.maxPixel(forPoints: 1000, scale: displayScale)) {
            Image(photo: cg, scale: displayScale, label: "Photo").resizable().scaledToFit()
        } else {
            KraftPhotoPlaceholder().aspectRatio(4.0 / 3.0, contentMode: .fit).padding(.horizontal, 12)
                .accessibilityLabel("Photo placeholder")
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { scale = max(1, baseScale * $0.magnification) }
            .onEnded { _ in
                baseScale = scale
                if scale <= 1 { offset = .zero; baseOffset = .zero }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                if scale > 1 { offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height) }
                else { dragDown = max(0, v.translation.height) }
            }
            .onEnded { v in
                if scale > 1 { baseOffset = offset }
                else {
                    if v.translation.height > 120 { close() }
                    withAnimation(.spring) { dragDown = 0 }
                }
            }
    }
}
