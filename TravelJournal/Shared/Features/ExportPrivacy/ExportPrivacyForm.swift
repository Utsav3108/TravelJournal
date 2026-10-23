import SwiftUI

/// The export privacy options as form sections, bound to one `ExportPrivacy` value. Used for the global defaults
/// (iPhone Settings, Mac Settings) and for a journey's own override. Put it inside a `Form` or `List`.
struct ExportPrivacyForm: View {
    @Binding var privacy: ExportPrivacy

    var body: some View {
        Section {
            OptionToggle(ExportPrivacyCopy.hideStayStops, detail: ExportPrivacyCopy.hideStayStopsDetail,
                         isOn: $privacy.hideStayStops, id: "privacyHideStay")
            OptionToggle(ExportPrivacyCopy.hideCosts, detail: ExportPrivacyCopy.hideCostsDetail,
                         isOn: $privacy.hideCosts, id: "privacyHideCosts")
            OptionToggle(ExportPrivacyCopy.hideExactTimes, detail: ExportPrivacyCopy.hideExactTimesDetail,
                         isOn: $privacy.hideExactTimes, id: "privacyHideTimes")
        } header: {
            Text("Hide on public exports")
        } footer: {
            Text(ExportPrivacyCopy.scopeFooter)
        }
        Section {
            Picker("Route map", selection: $privacy.mapMode) {
                ForEach(ExportPrivacy.MapMode.allCases, id: \.self) { mode in
                    Text(ExportPrivacyCopy.name(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("privacyMapMode")
        } header: {
            Text("Route map")
        } footer: {
            Text(ExportPrivacyCopy.detail(privacy.mapMode))
        }
    }
}

private struct OptionToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    let id: String

    init(_ title: String, detail: String, isOn: Binding<Bool>, id: String) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.id = id
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(KraftColor.ink)
                Text(detail).font(.footnote).foregroundStyle(KraftColor.inkSoft)
            }
        }
        .accessibilityIdentifier(id)
    }
}

/// A journey's choice between the app defaults and its own export privacy. Shared by the iPhone journey screen and
/// the Mac journey inspector; the Mac registers undo for `exportPrivacyData` around it.
struct JourneyExportPrivacySection: View {
    let journey: Journey
    var defaults: ExportPrivacyDefaults = .standard
    /// Not read directly: observing the key re-renders the section when the defaults change elsewhere.
    @AppStorage(ExportPrivacyDefaults.key) private var defaultsChanged: Data?

    var body: some View {
        Section {
            Toggle("Use app defaults", isOn: Binding(
                get: { journey.exportPrivacy == nil },
                set: { JourneyPrivacyOverride.setUsesDefaults($0, journey: journey, defaults: defaults) }))
                .accessibilityIdentifier("privacyUseDefaults")
        } header: {
            Text("Export privacy")
        } footer: {
            Text(journey.exportPrivacy == nil ? ExportPrivacyCopy.usesDefaultsFooter : ExportPrivacyCopy.customFooter)
        }
        if journey.exportPrivacy != nil {
            ExportPrivacyForm(privacy: Binding(
                get: { journey.exportPrivacy ?? defaults.load() },
                set: { JourneyPrivacyOverride.set($0, journey: journey) }))
        }
    }
}

/// The edits behind `JourneyExportPrivacySection`, kept apart from the view so they can be tested.
@MainActor
enum JourneyPrivacyOverride {
    /// Turning the defaults off seeds the override from the current defaults, so nothing changes until the user
    /// edits it; turning them back on drops the override.
    static func setUsesDefaults(_ usesDefaults: Bool, journey: Journey, defaults: ExportPrivacyDefaults) {
        if usesDefaults {
            guard journey.exportPrivacyData != nil else { return }
            journey.exportPrivacy = nil
        } else {
            guard journey.exportPrivacy == nil else { return }
            journey.exportPrivacy = defaults.load()
        }
        journey.updatedAt = .now
    }

    static func set(_ privacy: ExportPrivacy, journey: Journey) {
        guard journey.exportPrivacy != privacy else { return }
        journey.exportPrivacy = privacy
        journey.updatedAt = .now
    }
}

/// "Hide from public exports" for one stop: the explicit choice wins, else the category rule of the journey's
/// resolved privacy (Stay stops). Shared by the iPhone stop editor and the Mac stop inspector.
struct StopExportVisibilitySection: View {
    @Bindable var stop: Stop
    let journey: Journey
    var defaults: ExportPrivacyDefaults = .standard
    /// Not read directly: observing the key re-renders the section when the defaults change elsewhere.
    @AppStorage(ExportPrivacyDefaults.key) private var defaultsChanged: Data?

    var body: some View {
        let state = StopExportVisibility(stop: stop, privacy: ExportPrivacy.resolved(for: journey, defaults: defaults))
        Section {
            Toggle("Hide from public exports", isOn: Binding(
                get: { state.isHidden },
                set: { stop.exportHidden = $0 }))
                .accessibilityIdentifier("stopExportHidden")
            if state.isExplicit {
                Button("Reset to automatic") { stop.exportHidden = nil }
                    .accessibilityIdentifier("stopExportHiddenReset")
            }
        } header: {
            Text("Export privacy")
        } footer: {
            Text(state.footer)
        }
    }
}

/// The effective hide value of a stop and the words that explain it.
nonisolated struct StopExportVisibility: Equatable {
    var isHidden: Bool
    var isExplicit: Bool
    var isStay: Bool
    var hideStayStops: Bool

    init(exportHidden: Bool?, category: StopCategory?, privacy: ExportPrivacy) {
        isHidden = ExportPrivacy.isHidden(exportHidden: exportHidden, category: category,
                                          hideStayStops: privacy.hideStayStops)
        isExplicit = exportHidden != nil
        isStay = category == .stay
        hideStayStops = privacy.hideStayStops
    }

    @MainActor
    init(stop: Stop, privacy: ExportPrivacy) {
        self.init(exportHidden: stop.exportHidden, category: stop.category, privacy: privacy)
    }

    var footer: String {
        if isExplicit {
            return isHidden
                ? "Set for this stop: it is left out of the PDF and other public exports."
                : "Set for this stop: it appears in public exports."
        }
        if isStay && hideStayStops {
            return "Stay stops are hidden from public exports by default, so where you slept stays private."
        }
        return "Automatic: this stop appears in public exports. Your journal always keeps every stop."
    }
}

/// User-facing words for the export privacy options.
nonisolated enum ExportPrivacyCopy {
    static let hideStayStops = "Hide Stay stops"
    static let hideStayStopsDetail = "Hotels and other places you stayed are left out."
    static let hideCosts = "Hide costs"
    static let hideCostsDetail = "Prices and the total spent are left out."
    static let hideExactTimes = "Hide exact times"
    static let hideExactTimesDetail = "Times show as morning, afternoon or evening."
    static let scopeFooter = "Applies to what you share, such as the PDF (and Instagram later). "
        + "Your journal itself keeps everything."
    static let usesDefaultsFooter = "This story follows the export privacy in Settings."
    static let customFooter = "This story uses its own export privacy, below."

    static func name(_ mode: ExportPrivacy.MapMode) -> String {
        switch mode {
        case .show: "Show"
        case .zoomedOut: "Zoomed out"
        case .hidden: "Hidden"
        }
    }

    static func detail(_ mode: ExportPrivacy.MapMode) -> String {
        switch mode {
        case .show: "The route map shows each stop."
        case .zoomedOut: "The route map is zoomed out to the region, so exact places are hard to pick out."
        case .hidden: "The route map is left out."
        }
    }
}
