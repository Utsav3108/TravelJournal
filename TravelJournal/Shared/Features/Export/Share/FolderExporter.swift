import Foundation
import SwiftUI   // on macOS this also brings NSOpenPanel / NSWorkspace for the folder picker

/// Copies exported slides into a folder as "<Title> 01.jpg", "<Title> 02.jpg", ... Never overwrites: when any name in
/// the set is taken, the whole set gets the next free numeric suffix ("<Title> 2 01.jpg"...), so one export's files
/// stay together and in order. The core takes a destination URL so it can be tested; the Mac adds a folder picker.
nonisolated enum FolderExporter {
    enum Failure: LocalizedError, Equatable {
        case noImages
        case cannotWrite(String)

        var errorDescription: String? {
            switch self {
            case .noImages: "There are no slides to save."
            case .cannotWrite(let reason): "The slides could not be saved. \(reason)"
            }
        }
    }

    /// "A Day in Mumbai" x 12 -> "A Day in Mumbai 01.jpg" ... "A Day in Mumbai 12.jpg". `suffix` (2, 3, ...) goes
    /// between the title and the number. Numbers have at least two digits, more when `count` needs them.
    static func fileNames(title: String, count: Int, suffix: Int? = nil, pathExtension: String = "jpg") -> [String] {
        let stem = StoryPDFExporter.baseName(forTitle: title) + (suffix.map { " \($0)" } ?? "")
        let digits = max(2, String(max(count, 1)).count)
        return (1...max(count, 1)).prefix(count).map { i in
            "\(stem) \(String(repeating: "0", count: max(0, digits - String(i).count)))\(i).\(pathExtension)"
        }
    }

    /// The names `export` would write into `folder`: the plain set when none exists yet, else the first suffix
    /// (2, 3, ...) where none of the names exists.
    static func availableNames(title: String, count: Int, pathExtension: String = "jpg", in folder: URL,
                               fileManager: FileManager = .default) -> [String] {
        func free(_ names: [String]) -> Bool {
            !names.contains { fileManager.fileExists(atPath: folder.appendingPathComponent($0).path) }
        }
        let plain = fileNames(title: title, count: count, pathExtension: pathExtension)
        if free(plain) { return plain }
        var n = 2
        while true {
            let names = fileNames(title: title, count: count, suffix: n, pathExtension: pathExtension)
            if free(names) { return names }
            n += 1
        }
    }

    /// Copies `images` (in order) into `folder`; returns the written URLs. Starts security-scoped access on `folder`
    /// for the copy when it is a scoped URL (the Mac folder picker). On failure, files already written are removed.
    @discardableResult
    static func export(_ images: [URL], title: String, to folder: URL,
                       fileManager: FileManager = .default) throws -> [URL] {
        guard !images.isEmpty else { throw Failure.noImages }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let ext = images[0].pathExtension.isEmpty ? "jpg" : images[0].pathExtension.lowercased()
        let names = availableNames(title: title, count: images.count, pathExtension: ext, in: folder, fileManager: fileManager)
        var written: [URL] = []
        do {
            for (source, name) in zip(images, names) {
                let dest = folder.appendingPathComponent(name)
                try fileManager.copyItem(at: source, to: dest)
                written.append(dest)
            }
        } catch {
            for url in written { try? fileManager.removeItem(at: url) }
            throw Failure.cannotWrite(error.localizedDescription)
        }
        return written
    }
}

#if os(macOS)
extension FolderExporter {
    /// "Save to Folder…": asks for a folder (sheet on `window` when given), writes the slides and reveals them in
    /// Finder. Returns the written URLs, or nil when the user cancelled.
    @MainActor
    static func chooseFolderAndExport(_ images: [URL], title: String, window: NSWindow? = nil) async throws -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save"
        panel.message = "Choose a folder for the \(images.count) slide\(images.count == 1 ? "" : "s")."
        let response: NSApplication.ModalResponse
        if let window {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let folder = panel.url else { return nil }
        let urls = try export(images, title: title, to: folder)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        return urls
    }
}
#endif
