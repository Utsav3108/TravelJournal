#if os(macOS)
import SwiftUI

/// The shelf window: a sidebar (Journey, Map, Calendar, Settings) beside the selected screen.
struct MacShelfContainer: View {
    @State private var selection: ShelfSidebarItem? = .journey

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(ShelfSidebarItem.allCases) { item in
                    row(item)
                        .tag(item)
                        .selectionDisabled(!item.isAvailable)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch selection ?? .journey {
            case .map: StoryMapView()
            default: MacShelfView()
            }
        }
        .preferredColorScheme(.light)
    }

    private func row(_ item: ShelfSidebarItem) -> some View {
        HStack {
            Label(item.title, systemImage: item.symbol)
            if !item.isAvailable {
                Spacer()
                Text("Soon").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(item.isAvailable ? .primary : .secondary)
        .accessibilityIdentifier("sidebar-\(item.rawValue)")
    }
}
#endif
