import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

/// A journey as a PDF that is rendered only when something asks for the file (Share, and Phase 6's drag-out).
/// It goes through `StoryPDFExporter`, the same code path as Save, so every way out gives the same file.
/// Carries the journey's identifier and container (both Sendable) and hops to the main actor to read the journey.
struct JourneyPDF: Transferable, Sendable {
    let journeyID: PersistentIdentifier
    let container: ModelContainer

    /// nil when the journey is not in a model context.
    @MainActor
    init?(_ journey: Journey) {
        guard let container = journey.modelContext?.container else { return nil }
        self.journeyID = journey.persistentModelID
        self.container = container
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { pdf in
            SentTransferredFile(try await pdf.render())
        }
    }

    /// Renders the PDF into a temporary file named after the journey ("A Day in Mumbai.pdf").
    /// `exporter` is injectable for tests; `progress` is (pagesRendered, totalPages).
    @MainActor
    func render(exporter: StoryPDFExporter? = nil, progress: ((Int, Int) -> Void)? = nil) async throws -> URL {
        guard let journey = container.mainContext.model(for: journeyID) as? Journey else {
            throw StoryPDFExportError.cannotCreateFile
        }
        let exporter = exporter ?? StoryPDFExporter()
        if let progress { exporter.progress = progress }
        return try await exporter.export(journey)
    }
}
