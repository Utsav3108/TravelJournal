import SwiftUI
import UIKit

/// Toolbar-friendly "Export PDF" button: progress sheet (page i of n, cancel), then the share sheet
/// (includes Save to Files). Disabled when the journey has no stops.
struct StoryPDFExportButton: View {
    let journey: Journey

    @State private var task: Task<Void, Never>?
    @State private var progress: (done: Int, total: Int)?
    @State private var shareItem: ShareItem?
    @State private var errorMessage: String?

    private var hasStops: Bool { !journey.stops.isEmpty }
    private var isExporting: Bool { progress != nil }

    var body: some View {
        Button {
            start()
        } label: {
            Label("Export PDF", systemImage: "square.and.arrow.up")
        }
        .disabled(!hasStops || isExporting)
        .accessibilityIdentifier("exportPDF")
        .accessibilityHint(hasStops ? "Creates a printable PDF of this journey" : "Add at least one stop to export a PDF")
        .sheet(isPresented: Binding(get: { isExporting }, set: { _ in })) {
            ExportProgressView(done: progress?.done ?? 0, total: progress?.total ?? 0) { task?.cancel() }
                .presentationDetents([.height(220)])
                .interactiveDismissDisabled()
        }
        .sheet(item: $shareItem) { item in
            ActivityView(url: item.url).presentationDetents([.medium, .large])
        }
        .alert("Couldn't export PDF", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func start() {
        guard hasStops, task == nil else { return }
        progress = (0, 1)
        let exporter = StoryPDFExporter()
        exporter.progress = { done, total in progress = (done, total) }
        task = Task {
            defer { task = nil; progress = nil }
            do {
                let url = try await exporter.export(journey)
                progress = nil
                try? await Task.sleep(for: .milliseconds(350))   // let the progress sheet dismiss before presenting
                shareItem = ShareItem(url: url)
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ShareItem: Identifiable {
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
