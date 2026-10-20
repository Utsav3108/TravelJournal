import SwiftUI
import UIKit

/// Single export + share flow. The nav-bar button and the closing page's "Save as PDF" stamp both call `start()`.
@Observable
final class StoryPDFExportModel {
    let journey: Journey
    var progress: (done: Int, total: Int)?
    var shareItem: ShareItem?
    var errorMessage: String?
    private var task: Task<Void, Never>?

    init(journey: Journey) { self.journey = journey }

    var hasStops: Bool { !journey.stops.isEmpty }
    var isExporting: Bool { progress != nil }

    func cancel() { task?.cancel() }

    func start() {
        guard hasStops, task == nil else { return }
        progress = (0, 1)
        let exporter = StoryPDFExporter()
        exporter.progress = { [weak self] done, total in self?.progress = (done, total) }
        let journey = journey
        task = Task { [weak self] in
            defer { self?.task = nil; self?.progress = nil }
            do {
                let url = try await exporter.export(journey)
                self?.progress = nil
                try? await Task.sleep(for: .milliseconds(350))   // let the progress sheet dismiss before presenting
                self?.shareItem = ShareItem(url: url)
            } catch is CancellationError {
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }
}

/// Toolbar "Export PDF" button; presentations live in `.pdfExportPresentations(_:)`, attached once by the owner.
struct StoryPDFExportButton: View {
    let model: StoryPDFExportModel

    var body: some View {
        Button {
            model.start()
        } label: {
            Label("Export PDF", systemImage: "square.and.arrow.up")
        }
        .disabled(!model.hasStops || model.isExporting)
        .accessibilityIdentifier("exportPDF")
        .accessibilityHint(model.hasStops ? "Creates a printable PDF of this journey" : "Add at least one stop to export a PDF")
    }
}

extension View {
    /// Progress sheet, share sheet and error alert for a `StoryPDFExportModel`.
    func pdfExportPresentations(_ model: StoryPDFExportModel) -> some View {
        modifier(PDFExportPresentations(model: model))
    }
}

private struct PDFExportPresentations: ViewModifier {
    @Bindable var model: StoryPDFExportModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { model.isExporting }, set: { _ in })) {
                ExportProgressView(done: model.progress?.done ?? 0, total: model.progress?.total ?? 0) { model.cancel() }
                    .presentationDetents([.height(220)])
                    .interactiveDismissDisabled()
            }
            .sheet(item: $model.shareItem) { item in
                ActivityView(url: item.url).presentationDetents([.medium, .large])
            }
            .alert("Couldn't export PDF", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ExportProgressView: View {
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
            Button("Cancel", role: .cancel, action: cancel).accessibilityIdentifier("exportCancel")
        }
        .padding(24)
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
