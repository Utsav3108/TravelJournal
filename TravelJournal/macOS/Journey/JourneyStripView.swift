#if os(macOS)
import SwiftUI

/// The story as one horizontal strip: the same page components as the iPhone pager, placed edge to edge by
/// `StripComposer`. Trackpads scroll sideways natively; a plain mouse wheel is bridged to horizontal movement.
struct JourneyStripView: View {
    @Bindable var model: JourneyWindowModel

    @State private var position = ScrollPosition()
    @State private var legCard: StoryLeg?
    @State private var photoCard: StoryPhoto?
    @State private var pointer: CGPoint = .zero
    @FocusState private var focused: Bool

    private static let space = "strip"

    var body: some View {
        GeometryReader { geo in
            let size = StripComposer.pageSize(viewportHeight: geo.size.height, zoom: model.zoom)
            let pages = model.items.map(\.page)
            ZStack {
                PaperBackground().ignoresSafeArea()
                ScrollView([.horizontal, .vertical]) {
                    HStack(spacing: 0) {
                        if StripComposer.isMeasured(geo.size) {
                            ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                                pageView(item, index: i, size: size, pages: pages)
                            }
                        }
                    }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)   // short strips sit centred
                }
                .scrollPosition($position)
                .background(WheelScrollBridge(isEnabled: model.zoom <= 1))
            }
            .coordinateSpace(name: Self.space)
            .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
                if case .active(let p) = phase, legCard == nil, photoCard == nil { pointer = p }
            }
            .overlay(alignment: .topLeading) {
                // Pages report a tapped leg or photo without a position, so the popovers hang off the last pointer location.
                Color.clear.frame(width: 1, height: 1).position(pointer)
                    .popover(item: $legCard) { leg in
                        LegCardView(leg: leg).padding(20).frame(width: 340, height: 280)
                    }
                    .popover(item: $photoCard) { photo in
                        PhotoCardView(photo: photo, size: PhotoCardLayout.size(viewport: geo.size))
                    }
            }
            .onChange(of: geo.size, initial: true) { _, new in model.viewport = new }
            .onChange(of: model.centerRequest) { _, request in
                guard let request else { return }
                center(pageID: request.pageID, size: size, viewport: geo.size)
            }
            .onChange(of: model.zoom) {
                if let i = model.selectedIndex { center(pageID: model.items[i].id, size: size, viewport: geo.size) }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(keys: [.leftArrow], phases: [.down, .repeat]) { press in step(-1, press) }
        .onKeyPress(keys: [.rightArrow], phases: [.down, .repeat]) { press in step(1, press) }
        .onKeyPress(keys: [.space], phases: [.down, .repeat, .up]) { press in hold(press) }
        .accessibilityIdentifier("storyStrip")
    }

    /// Hold Space to dictate into the selected stop (edit mode only, never while typing in a field).
    private func hold(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty, !TextInputFocus.isEditing else { return .ignored }
        switch press.phase {
        case .down:
            guard model.voiceStop != nil else { return .ignored }
            model.voicePress()
            return .handled
        case .repeat:
            return model.voice?.phase == .listening ? .handled : .ignored   // key auto-repeat
        case .up:
            guard model.voice?.phase == .listening else { return .ignored }
            model.voiceRelease()
            return .handled
        default:
            return .ignored
        }
    }

    private func step(_ direction: Int, _ press: KeyPress) -> KeyPress.Result {
        // Option-Command-arrows are reserved for moving stops; arrows never fire while a text field is being edited.
        guard press.modifiers.isEmpty, !TextInputFocus.isEditing else { return .ignored }
        model.step(direction)
        return .handled
    }

    private func center(pageID: String, size: CGSize, viewport: CGSize) {
        guard let i = model.items.firstIndex(where: { $0.id == pageID }) else { return }
        let x = StripComposer.centeredOffset(index: i, pageWidth: size.width, viewportWidth: viewport.width,
                                             count: model.items.count)
        withAnimation(.easeInOut(duration: 0.35)) { position.scrollTo(x: x) }
    }

    private func pageView(_ item: StripComposer.Item, index: Int, size: CGSize, pages: [StoryPage]) -> some View {
        let metrics = PageMetrics.phone(size)
        let stopID = item.stopID
        // No outline on the pages: the strip is one continuous sheet, and a border would cut the route at every seam.
        // Selection and hover are shown in the sidebar.
        return StoryPageView(page: item.page, metrics: metrics,
                             callbacks: StoryPageCallbacks(onPhotoTap: { photoCard = $0 }, onLegTap: { leg in
                                 // With the inspector open a leg click selects the leg for editing; otherwise it is a glance popover.
                                 if model.inspectorShown { model.selectLeg(leg.id) } else { legCard = leg }
                             }),
                             entryY: StopLayout.entryY(at: index, in: pages, metrics: metrics))
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture {   // child taps (legs) win
                if let stopID { model.select(stopID, center: false) }
                focused = true
            }
            .onHover { inside in if let stopID { model.hover(stopID, isInside: inside) } }
            .id(item.id)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(StoryViewerLogic.pageLabel(item.page, index: index, total: model.items.count))
    }
}
#endif
