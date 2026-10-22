#if os(macOS)
import SwiftUI

/// Runs one export or print at a time for the whole app. The windows that can start one (a journey window, the shelf)
/// each host the progress sheet, save panel and error alert, but only the host whose `origin` started the job shows them.
@MainActor
@Observable
final class MacExportCoordinator {
    static let shared = MacExportCoordinator()

    enum Origin: Hashable { case shelf, journey(UUID) }
    enum Purpose { case save, print }

    /// Which window started the latest job; never cleared, because the visibility flags below say what is showing.
    private(set) var origin: Origin?
    private(set) var progress: (done: Int, total: Int)?
    var isPresentingSave = false
    private(set) var document: PDFFileDocument?
    private(set) var documentName = "Journey"
    var errorMessage: String?

    /// Injectable for tests.
    var makeExporter: () -> StoryPDFExporter = { StoryPDFExporter() }
    var printHandler: (Data, String) -> Void = { PrintBridge.print(pdfData: $0, title: $1) }

    private var task: Task<Void, Never>?

    var isExporting: Bool { progress != nil }
    var isBusy: Bool { task != nil || isPresentingSave }

    /// Export and Print need at least one stop.
    static func canExport(_ journey: Journey) -> Bool { !journey.stops.isEmpty }

    func start(_ journey: Journey, purpose: Purpose, origin: Origin) {
        guard !isBusy, Self.canExport(journey), let pdf = JourneyPDF(journey) else { return }
        self.origin = origin
        errorMessage = nil
        progress = (0, 1)
        let title = journey.title
        let name = StoryPDFExporter.fileName(forTitle: title)
        let exporter = makeExporter()
        task = Task { [weak self] in
            defer { self?.task = nil; self?.progress = nil }
            do {
                let url = try await pdf.render(exporter: exporter) { done, total in self?.progress = (done, total) }
                let data = try Data(contentsOf: url)
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                self?.progress = nil
                try? await Task.sleep(for: .milliseconds(350))   // let the progress sheet dismiss before presenting
                switch purpose {
                case .save:
                    self?.documentName = (name as NSString).deletingPathExtension
                    self?.document = PDFFileDocument(data: data)
                    self?.isPresentingSave = true
                case .print:
                    self?.printHandler(data, title)
                }
            } catch is CancellationError {
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() { task?.cancel() }

    /// Called when the Save panel closes, whatever the outcome.
    func saveFinished(_ result: Result<URL, Error>? = nil) {
        if case .failure(let error)? = result, (error as? CocoaError)?.code != .userCancelled {
            errorMessage = error.localizedDescription
        }
        isPresentingSave = false
        document = nil
    }
}
#endif
