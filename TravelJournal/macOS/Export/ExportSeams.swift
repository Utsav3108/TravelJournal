#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

// Phase 5b. The journey toolbar, the journey window's presentations and the shelf book's context menu call these
// (the names and signatures were fixed by the Phase 5 seams).

/// What the front journey window offers the menu bar: File → Export as PDF… and Print…. nil (journey without stops)
/// greys both out.
struct ExportActions {
    var export: () -> Void
    var print: () -> Void
}

private struct ExportActionsKey: FocusedValueKey { typealias Value = ExportActions }

extension FocusedValues {
    var exportActions: ExportActions? {
        get { self[ExportActionsKey.self] }
        set { self[ExportActionsKey.self] = newValue }
    }
}

/// Export and Share items for a journey window's toolbar.
struct JourneyExportToolbar: ToolbarContent {
    let journey: Journey

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                MacExportCoordinator.shared.requestExport(journey, origin: .journey(journey.id))
            } label: {
                Label("Export", systemImage: "arrow.down.document")
            }
            .disabled(!MacExportCoordinator.canExport(journey) || MacExportCoordinator.shared.isBusy)
            .help("Export this journey as a PDF or Instagram post")
            .accessibilityIdentifier("exportPDF")
        }
        ToolbarItem(placement: .primaryAction) {
            if let pdf = JourneyPDF(journey) {
                ShareLink(item: pdf, preview: SharePreview(journey.title.isEmpty ? "Story" : journey.title)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(!MacExportCoordinator.canExport(journey))
                .help("Share this journey as a PDF")
                .accessibilityIdentifier("sharePDF")
            }
        }
    }
}

extension View {
    /// Progress sheet, save panel and error alert for exporting or printing a journey, plus the File-menu actions.
    func journeyExportPresentations(journey: Journey) -> some View {
        modifier(ExportHost(origin: .journey(journey.id), journey: journey))
    }

    /// The same presentations for the shelf window, whose context menu starts exports for the clicked book.
    func shelfExportPresentations() -> some View {
        modifier(ExportHost(origin: .shelf, journey: nil))
    }
}

/// Export as PDF… and Print… for a book in the shelf's context menu.
struct ExportContextMenuItems: View {
    let journey: Journey

    var body: some View {
        let busy = MacExportCoordinator.shared.isBusy
        Divider()
        Button("Export…") {
            MacExportCoordinator.shared.requestExport(journey, origin: .shelf)
        }
        .disabled(!MacExportCoordinator.canExport(journey) || busy)
        Button("Print…") {
            MacExportCoordinator.shared.start(journey, purpose: .print, origin: .shelf)
        }
        .disabled(!MacExportCoordinator.canExport(journey) || busy)
    }
}

private struct ExportHost: ViewModifier {
    let origin: MacExportCoordinator.Origin
    let journey: Journey?

    private var coordinator: MacExportCoordinator { .shared }

    func body(content: Content) -> some View {
        let mine = coordinator.origin == origin
        content
            .focusedSceneValue(\.exportActions, actions)
            .background {
                if mine, let flow = coordinator.flow {
                    Color.clear.exportFlowPresentations(flow)
                }
            }
            .sheet(isPresented: Binding(get: { mine && coordinator.isExporting }, set: { _ in })) {
                ExportProgressSheet(done: coordinator.progress?.done ?? 0, total: coordinator.progress?.total ?? 0) {
                    coordinator.cancel()
                }
            }
            .fileExporter(isPresented: Binding(get: { mine && coordinator.isPresentingSave },
                                               set: { if !$0 { coordinator.saveFinished() } }),
                          document: coordinator.document, contentType: .pdf,
                          defaultFilename: coordinator.documentName) { coordinator.saveFinished($0) }
            .alert("Couldn't export PDF",
                   isPresented: Binding(get: { mine && coordinator.errorMessage != nil },
                                        set: { if !$0 { coordinator.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(coordinator.errorMessage ?? "")
            }
    }

    private var actions: ExportActions? {
        guard let journey, MacExportCoordinator.canExport(journey) else { return nil }
        return ExportActions(
            export: { MacExportCoordinator.shared.requestExport(journey, origin: origin) },
            print: { MacExportCoordinator.shared.start(journey, purpose: .print, origin: origin) })
    }
}

private struct ExportProgressSheet: View {
    let done: Int
    let total: Int
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Making your PDF").font(.headline)
            ProgressView(value: Double(done), total: Double(max(total, 1)))
            Text(done == 0 ? "Preparing map and photos" : "Page \(min(done, total)) of \(total)")
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("exportProgressText")
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("exportCancel")
        }
        .padding(24)
        .frame(width: 320)
        .interactiveDismissDisabled()
    }
}
#endif
