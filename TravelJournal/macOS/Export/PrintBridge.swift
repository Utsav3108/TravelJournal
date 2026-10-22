#if os(macOS)
import AppKit
import PDFKit

/// The one AppKit touchpoint for printing: SwiftUI has no print API, so the PDF goes to the system print dialog
/// through PDFKit's print operation. The PDF stays in memory (the temporary file is already gone).
@MainActor
enum PrintBridge {
    @discardableResult
    static func print(pdfData: Data, title: String) -> Bool {
        guard let document = PDFDocument(data: pdfData),
              let operation = document.printOperation(for: NSPrintInfo.shared.copy() as? NSPrintInfo,
                                                      scalingMode: .pageScaleToFit, autoRotate: true) else { return false }
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
        return true
    }
}
#endif
