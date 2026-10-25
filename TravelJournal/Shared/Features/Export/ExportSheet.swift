import SwiftUI

/// The Export sheet: format, live preview of the first slide, this journey's privacy, which stops go in, Export.
/// Every choice here is saved on the journey as it is made.
struct ExportSheet: View {
    @Bindable var model: ExportFlowModel

    var body: some View {
        let journey = model.journey
        let privacy = model.privacy
        let stops = journey.orderedStops
        Form {
            Section {
                Picker("Format", selection: $model.format) {
                    ForEach(ExportFormat.allCases) { Text($0.shortName).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("exportFormat")
                Text(model.format.detail)
                    .font(.footnote).foregroundStyle(KraftColor.inkSoft)
            }
            Section {
                HStack {
                    Spacer()
                    ExportThumbnail(journey: journey, options: model.options(),
                                    stopSignature: stops.map(\.exportHidden))
                        .frame(maxHeight: 240)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section {
                Toggle(isOn: Binding(get: { privacy.showBrandStamp }, set: { model.setBrandStamp($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ExportPrivacyCopy.brandStamp)
                        Text(ExportPrivacyCopy.brandStampDetail).font(.footnote).foregroundStyle(KraftColor.inkSoft)
                    }
                }
                .accessibilityIdentifier("exportStamp")
            }
            JourneyExportPrivacySection(journey: journey, defaults: .standard)
            Section {
                ForEach(stops) { stop in
                    let state = StopExportVisibility(stop: stop, privacy: privacy)
                    Toggle(isOn: Binding(get: { !state.isHidden }, set: { model.setStop(stop, shown: $0) })) {
                        Text(stop.placeName.isEmpty ? "Untitled stop" : stop.placeName).lineLimit(1)
                    }
                    .accessibilityIdentifier("exportStop-\(stop.id.uuidString)")
                }
            } header: {
                Text("Stops")
            } footer: {
                Text("Hidden stops are left out of what you share. Your journal keeps every stop.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .safeAreaInset(edge: .bottom) { exportBar }
        .accessibilityIdentifier("exportSheet")
    }

    private var exportBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                model.requestExport()
            } label: {
                Text("Export").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.hasStops)
            .accessibilityIdentifier("exportConfirm")
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(.bar)
    }
}

extension ExportFormat {
    /// Segment label.
    var shortName: String {
        switch self {
        case .pdf: "PDF"
        case .carousel: "Carousel"
        case .story: "Story"
        }
    }

    /// One line under the picker.
    var detail: String {
        switch self {
        case .pdf: "A printable A4 file you can share or save."
        case .carousel: "Swipeable 4:5 slides for an Instagram post, up to 20."
        case .story: "Tall 9:16 frames for Instagram Stories."
        }
    }
}
