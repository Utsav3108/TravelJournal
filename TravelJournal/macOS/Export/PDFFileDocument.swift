#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// The rendered PDF handed to the Save panel (`.fileExporter`).
struct PDFFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
