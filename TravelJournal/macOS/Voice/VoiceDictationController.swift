#if os(macOS)
import Foundation

/// Drives one hold-to-speak dictation into the selected stop: listen, extract, write the fields, offer undo.
///
/// Values are written in one pass, so the inspector's undo tracking sees a single edit and ⌘Z reverts the stop
/// fields in one step; the card's Undo also restores "Got here by" (the leg isn't part of the stop's tracked
/// snapshot). Only the row highlights are staggered, one field every `revealInterval`.
@MainActor
@Observable
final class VoiceDictationController {
    enum Phase: Equatable {
        case idle
        case listening
        case processing
        case filled([VoiceField])
        case failed(VoiceError)
    }

    private(set) var phase: Phase = .idle
    /// What has been heard so far; the final text once processing starts.
    private(set) var transcript = ""
    /// Fields whose row should currently show the fill highlight.
    private(set) var freshFields: Set<VoiceField> = []
    /// False on devices without Apple Intelligence: the voice UI isn't shown at all.
    let isAvailable: Bool

    var isBusy: Bool { phase == .listening || phase == .processing }

    private struct Target {
        let stop: Stop
        let journey: Journey
    }
    private struct Snapshot {
        let stop: StopContent
        let leg: LegContent?
    }

    private let capture: SpeechCapturing
    private let extractor: DraftExtracting
    private let revealInterval: Duration
    private let freshDuration: Duration

    private var target: Target?
    private var snapshot: Snapshot?
    private var startTask: Task<AsyncStream<String>, Error>?
    private var transcriptTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?

    init(capture: SpeechCapturing, extractor: DraftExtracting, isAvailable: Bool,
         revealInterval: Duration = .milliseconds(230), freshDuration: Duration = .milliseconds(1100)) {
        self.capture = capture
        self.extractor = extractor
        self.isAvailable = isAvailable
        self.revealInterval = revealInterval
        self.freshDuration = freshDuration
    }

    /// Button or Space went down. Ignored while a dictation is already running or on unsupported devices.
    func begin(on stop: Stop, journey: Journey) {
        guard isAvailable, !isBusy else { return }
        flashTask?.cancel()
        freshFields = []
        snapshot = nil
        target = Target(stop: stop, journey: journey)
        transcript = ""
        phase = .listening

        let start = Task { try await capture.start() }
        startTask = start
        transcriptTask = Task {
            do {
                for await text in try await start.value { transcript = text }
            } catch {
                fail(error as? VoiceError ?? .speechModelUnavailable)
            }
        }
    }

    /// Button or Space came up: finish listening and fill the stop in.
    func end() {
        guard phase == .listening else { return }
        phase = .processing
        Task { await finish() }
    }

    /// "Undo" on the card: put the stop (and its incoming leg) back as they were before this dictation.
    func undo() {
        guard case .filled = phase, let target, let snapshot else { return }
        snapshot.stop.apply(to: target.stop)
        if let leg = snapshot.leg, let incoming = target.stop.incomingLeg { leg.apply(to: incoming) }
        dismiss()
    }

    /// "Looks right", or selecting another stop: clear the summary.
    func dismiss() {
        guard !isBusy else { return }
        flashTask?.cancel()
        freshFields = []
        snapshot = nil
        phase = .idle
    }

    private func finish() async {
        do {
            _ = try await startTask?.value
            let text = try await capture.finish().trimmingCharacters(in: .whitespacesAndNewlines)
            guard phase == .processing else { return }   // the start failed while the button was still down
            guard !text.isEmpty else { return fail(.noSpeech) }
            transcript = text

            let draft: VoiceStopDraft
            do { draft = try await extractor.extract(from: text) } catch { return fail(.extractionFailed) }
            guard phase == .processing, let target else { return }
            fill(draft, in: target)
        } catch {
            fail(error as? VoiceError ?? .speechModelUnavailable)
        }
    }

    private func fill(_ draft: VoiceStopDraft, in target: Target) {
        let stop = target.stop
        let changes = VoiceDraftApplier.changes(
            for: draft, current: StopContent(stop), incomingLeg: stop.incomingLeg.map(LegContent.init),
            arrivalBase: stop.arrivalTime ?? target.journey.date,
            timeZone: TimeZone(identifier: target.journey.timeZoneID) ?? .current)
        guard !changes.isEmpty else { return fail(.nothingToFill) }

        snapshot = Snapshot(stop: StopContent(stop), leg: stop.incomingLeg.map(LegContent.init))
        for change in changes { VoiceDraftApplier.apply(change, to: stop) }
        let fields = changes.map(\.field)
        phase = .filled(fields)
        flash(fields)
    }

    private func flash(_ fields: [VoiceField]) {
        flashTask?.cancel()
        flashTask = Task {
            for field in fields {
                try? await Task.sleep(for: revealInterval)
                guard !Task.isCancelled else { return }
                freshFields.insert(field)
            }
            try? await Task.sleep(for: freshDuration)
            guard !Task.isCancelled else { return }
            freshFields = []
        }
    }

    private func fail(_ error: VoiceError) {
        guard phase == .listening || phase == .processing else { return }
        capture.cancel()
        transcriptTask?.cancel()
        phase = .failed(error)
    }
}
#endif
