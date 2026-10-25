import SwiftUI

/// The whole export flow for one journey: options sheet, the over-20 carousel decision, the stop picker, progress and
/// the result. One model per presentation; the iPhone story viewer and the Mac `MacExportCoordinator` each own one.
/// Rendering goes through an injected `ExportPipeline`, so tests drive it with fake renderers.
@MainActor
@Observable
final class ExportFlowModel {
    enum Step: Equatable {
        case idle
        /// The Export sheet.
        case options
        /// The Export sheet with the "needs N slides" alert on top.
        case askingCarousel(slides: Int)
        /// Choose which stops go into the carousel.
        case picking
        case exporting
        /// A finished PDF, offered in a share sheet (iPhone).
        case pdfReady(URL)
        /// A finished PDF handed to the Mac Save panel.
        case pdfSave(data: Data, name: String)
        /// Finished slides / frames, shown in `SlidePreviewView`.
        case slides([URL])
    }

    static let pdfNote = "A PDF can be shared as a file but not posted as an Instagram carousel."

    let journey: Journey
    private let pipeline: ExportPipeline
    private let defaults: ExportPrivacyDefaults
    /// Pause before a different presentation follows a dismissed one (the Mac Save panel).
    var presentationDelay: Duration
    /// Mac saves the PDF through the Save panel; iPhone shows a share sheet.
    var savesPDFWithPanel: Bool
    /// Called once when the flow returns to idle after having started (the Mac coordinator drops it).
    @ObservationIgnored var onFinish: (() -> Void)?

    private(set) var step: Step = .idle
    var format: ExportFormat = .pdf
    private(set) var progress: (done: Int, total: Int) = (0, 1)
    var errorMessage: String?
    /// Shown with the PDF when the user declined the Instagram carousel.
    private(set) var note: String?
    /// Stops ticked in the picker (`Stop.id`).
    private(set) var pickerSelection: Set<UUID> = []
    /// Slides the current picker selection makes.
    private(set) var pickerCount = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(journey: Journey, pipeline: ExportPipeline? = nil, defaults: ExportPrivacyDefaults = .standard,
         presentationDelay: Duration = .milliseconds(350), savesPDFWithPanel: Bool? = nil) {
        self.journey = journey
        self.pipeline = pipeline ?? ExportPipeline()
        self.defaults = defaults
        self.presentationDelay = presentationDelay
        #if os(macOS)
        self.savesPDFWithPanel = savesPDFWithPanel ?? true
        #else
        self.savesPDFWithPanel = savesPDFWithPanel ?? false
        #endif
    }

    // MARK: State

    var hasStops: Bool { !journey.stops.isEmpty }
    var isExporting: Bool { step == .exporting }
    var isActive: Bool { step != .idle }
    var maxSlices: Int { ExportFormat.carousel.spec.maxSlices ?? 20 }

    /// The privacy this export uses: the journey's own, else the app defaults.
    var privacy: ExportPrivacy { ExportPrivacy.resolved(for: journey, defaults: defaults) }

    func options(includedStopIDs: Set<UUID>? = nil, format: ExportFormat? = nil) -> ExportOptions {
        ExportOptions(format: format ?? self.format, privacy: privacy, includedStopIDs: includedStopIDs)
    }

    /// Slides / pages the given options would make.
    func estimate(_ options: ExportOptions) -> Int { pipeline.estimateSlices(journey, options: options) }

    /// Stops privacy leaves in, in order. These are the picker's rows.
    var visibleStops: [Stop] {
        let p = privacy
        return journey.orderedStops.filter { !p.isHidden($0) }
    }

    var canPickerExport: Bool { pickerCount > 0 && pickerCount <= maxSlices }

    // MARK: Privacy edits (persist on the journey)

    /// The quick stamp toggle: edits the effective privacy, creating the journey's override when it follows the defaults.
    func setBrandStamp(_ on: Bool) {
        var p = privacy
        guard p.showBrandStamp != on else { return }
        p.showBrandStamp = on
        JourneyPrivacyOverride.set(p, journey: journey)
    }

    /// Per-stop "show in export" toggle; an explicit choice, like the stop editor's.
    func setStop(_ stop: Stop, shown: Bool) {
        stop.exportHidden = !shown
        journey.updatedAt = .now
    }

    // MARK: Steps

    func present() {
        guard hasStops, step == .idle else { return }
        started = true
        errorMessage = nil
        note = nil
        step = .options
    }

    /// Export tapped in the sheet.
    func requestExport() {
        guard step == .options, hasStops else { return }
        let count = estimate(options())
        if format == .carousel, count > maxSlices {
            step = .askingCarousel(slides: count)
        } else {
            run(options())
        }
    }

    private var isAsking: Bool { if case .askingCarousel = step { true } else { false } }

    /// "Yes": pick stops for the carousel.
    func chooseCarouselAnyway() {
        guard isAsking else { return }
        pickerSelection = Set(visibleStops.map(\.id))
        updatePickerCount()
        step = .picking
    }

    /// "No": the full journey as a PDF.
    func declineCarousel() {
        guard isAsking else { return }
        format = .pdf
        note = Self.pdfNote
        run(options(includedStopIDs: nil, format: .pdf))
    }

    func togglePicked(_ stop: Stop) {
        guard step == .picking else { return }
        if pickerSelection.contains(stop.id) { pickerSelection.remove(stop.id) } else { pickerSelection.insert(stop.id) }
        updatePickerCount()
    }

    func exportPicked() {
        guard step == .picking, canPickerExport else { return }
        run(options(includedStopIDs: pickerSelection, format: .carousel))
    }

    func backToOptions() {
        if step == .picking || isAsking { step = .options }
    }

    private func updatePickerCount() {
        pickerCount = estimate(options(includedStopIDs: pickerSelection, format: .carousel))
    }

    // MARK: Running

    private func run(_ options: ExportOptions) {
        guard task == nil else { return }
        progress = (0, 1)
        step = .exporting
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                let result = try await self.pipeline.render(self.journey, options: options) { [weak self] done, total in
                    self?.progress = (done, total)
                }
                await self.finish(result)
            } catch is CancellationError {
                self.step = .options
            } catch {
                self.step = .options
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Resolves once the task has finished (tests).
    func waitForExport() async { await task?.value }

    private func finish(_ result: ExportResult) async {
        switch result {
        case .images(let urls):
            step = .slides(urls)
        case .pdf(let url):
            guard savesPDFWithPanel else { step = .pdfReady(url); return }
            do {
                let data = try Data(contentsOf: url)
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                step = .idle   // close the sheet, then open the panel
                if presentationDelay > .zero { try? await Task.sleep(for: presentationDelay) }
                step = .pdfSave(data: data, name: (url.lastPathComponent as NSString).deletingPathExtension)
            } catch {
                step = .options
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() { task?.cancel() }

    /// Closes the flow from any step. While exporting it cancels, and the flow returns to the options.
    func dismiss() {
        if step == .exporting { task?.cancel(); return }
        end()
    }

    /// The Save panel or share sheet closed. A panel failure (not a cancel) is reported.
    func saveFinished(_ result: Result<URL, Error>? = nil) {
        if case .failure(let error)? = result, (error as? CocoaError)?.code != .userCancelled {
            errorMessage = error.localizedDescription
            step = .options
            return
        }
        end()
    }

    private func end() {
        guard started else { return }
        cleanUpFiles()
        step = .idle
        started = false
        onFinish?()
    }

    private func cleanUpFiles() {
        switch step {
        case .pdfReady(let url): try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        case .slides(let urls):
            if let first = urls.first { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }
        default: break
        }
    }
}
