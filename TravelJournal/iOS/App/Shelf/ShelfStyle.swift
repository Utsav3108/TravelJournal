import SwiftUI
import SwiftData

/// Home-screen shelf looks. The shelf has its own look, separate from the Vintage Kraft story theme.
/// Each case is rendered by one self-contained view (see `ShelfStyleContent`), so styles are independent.
enum ShelfStyle: String, CaseIterable, Identifiable {
    case woodenBookcase
    case coverRack
    case deskStack
    case floatingShelves

    static let storageKey = "shelfStyle"
    static let `default`: ShelfStyle = .woodenBookcase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .woodenBookcase: "Wooden Bookcase"
        case .coverRack: "Cover Rack"
        case .deskStack: "Desk Stack"
        case .floatingShelves: "Floating Shelves"
        }
    }

    var blurb: String {
        switch self {
        case .woodenBookcase: "Spines standing on warm wooden planks. Tap one to pull it out."
        case .coverRack: "Covers facing out on a rack. Swipe through like a bookstore display."
        case .deskStack: "Books piled on a desk, spines showing. Tap one to open it."
        case .floatingShelves: "Dark, moody ledges with covers on display."
        }
    }

    var symbol: String {
        switch self {
        case .woodenBookcase: "books.vertical"
        case .coverRack: "square.stack.3d.forward.dottedline"
        case .deskStack: "text.book.closed"
        case .floatingShelves: "rectangle.split.3x1"
        }
    }

    /// True when the style's background is dark, so the nav bar uses light text.
    var usesDarkChrome: Bool { self == .floatingShelves }

    /// Nav bar fill for dark styles; matches the top of the floating-shelves wall.
    static let darkChromeColor = Color(hex: 0x10141D)

}

/// What every shelf style receives. Styles draw their own full-screen background and books;
/// the host owns navigation, the toolbar, the title and the delete confirmation.
struct ShelfStyleContext {
    let journeys: [Journey]
    let open: (Journey) -> Void
    let requestDelete: (Journey) -> Void
}

/// Dispatches to the view for the chosen style.
struct ShelfStyleContent: View {
    let style: ShelfStyle
    let context: ShelfStyleContext

    var body: some View {
        switch style {
        case .woodenBookcase: WoodenBookcaseShelfView(context: context)
        case .coverRack: CoverRackShelfView(context: context)
        case .deskStack: DeskStackShelfView(context: context)
        case .floatingShelves: FloatingShelvesShelfView(context: context)
        }
    }
}

/// Bottom sheet for trying shelf looks. Tapping a row applies it live behind the sheet.
struct ShelfStylePicker: View {
    @Binding var selection: ShelfStyle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ShelfStyle.allCases) { style in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { selection = style }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: style.symbol)
                            .font(.title2).frame(width: 36)
                            .foregroundStyle(KraftColor.route)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.title).font(.headline).foregroundStyle(KraftColor.ink)
                            Text(style.blurb).font(.footnote).foregroundStyle(KraftColor.inkSoft)
                        }
                        Spacer()
                        if style == selection {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(KraftColor.route)
                        }
                    }
                }
                .accessibilityIdentifier("shelfStyle_\(style.rawValue)")
                .accessibilityAddTraits(style == selection ? .isSelected : [])
            }
            .navigationTitle("Shelf style")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.height(400), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(400)))
    }
}
