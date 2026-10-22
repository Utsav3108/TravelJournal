#if os(macOS)
import SwiftUI

/// The story as one horizontal strip: the same page components as the iPhone pager, placed edge to edge by
/// `StripComposer`. Trackpads scroll sideways natively; a plain mouse wheel is bridged to horizontal movement.
struct JourneyStripView: View {
    @Bindable var model: JourneyWindowModel

    @State private var position = ScrollPosition()
    @State private var legCard: StoryLeg?
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
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                            pageView(item, index: i, size: size, pages: pages)
                        }
                    }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)   // short strips sit centred
                }
                .scrollPosition($position)
                .background(WheelScrollBridge(isEnabled: model.zoom <= 1))
            }
            .coordinateSpace(name: Self.space)
            .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
                if case .active(let p) = phase, legCard == nil { pointer = p }
            }
            .overlay(alignment: .topLeading) {
                // Pages report a tapped leg without a position, so the popover hangs off the last pointer location.
                Color.clear.frame(width: 1, height: 1).position(pointer)
                    .popover(item: $legCard) { leg in
                        LegCardView(leg: leg).padding(20).frame(width: 340, height: 280)
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
        .accessibilityIdentifier("storyStrip")
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
        let active = stopID != nil && stopID == model.selectedStopID
        let hovered = stopID != nil && stopID == model.hoveredStopID
        return StoryPageView(page: item.page, metrics: metrics,
                             callbacks: StoryPageCallbacks(onLegTap: { legCard = $0 }),
                             entryY: StopLayout.entryY(at: index, in: pages, metrics: metrics))
            .frame(width: size.width, height: size.height)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(KraftColor.route.opacity(active ? 0.85 : hovered ? 0.4 : 0), lineWidth: 3)
                    .allowsHitTesting(false)
            }
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
