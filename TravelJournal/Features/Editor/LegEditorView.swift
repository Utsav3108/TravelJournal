import SwiftUI
import SwiftData

struct LegEditorView: View {
    @Bindable var leg: Leg
    @State private var kmText = ""
    @State private var minText = ""

    var body: some View {
        Form {
            Section("Transport") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(TransportMode.allCases, id: \.self) { m in
                        let selected = leg.modeWasChosen && leg.mode == m
                        Button { leg.mode = m } label: {
                            VStack(spacing: 4) {
                                TransportIcon(mode: m.icon, size: 28)
                                Text(EditorLogic.modeName(m)).font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
                                    .foregroundStyle(KraftColor.ink)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? KraftColor.kraft.opacity(0.5) : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(selected ? KraftColor.kraftDark : KraftColor.paperEdge, lineWidth: selected ? 1.5 : 0.5))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(EditorLogic.modeName(m))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Distance and time (optional)") {
                HStack {
                    Text("Distance")
                    TextField("km", text: $kmText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("km").foregroundStyle(KraftColor.inkSoft)
                }
                HStack {
                    Text("Duration")
                    TextField("min", text: $minText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    Text("min").foregroundStyle(KraftColor.inkSoft)
                }
            }
            Section {
                TextEditor(text: Binding(
                    get: { leg.story ?? "" },
                    set: { new in
                        let t = EditorLogic.limitedStory(new, limit: EditorLogic.legStoryWordLimit)
                        leg.story = t.isEmpty ? nil : t
                    }))
                    .font(KraftFont.note(18, scaled: true))
                    .frame(minHeight: 90)
            } header: { Text("Leg story") } footer: {
                HStack { Spacer(); WordCounter(text: leg.story ?? "", limit: EditorLogic.legStoryWordLimit) }
            }
        }
        .foregroundStyle(KraftColor.ink)
        .calmForm()
        .navigationTitle("Travel details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            kmText = leg.distanceKm.map(EditorLogic.formatKm) ?? ""
            minText = leg.durationMinutes.map(String.init) ?? ""
        }
        .onChange(of: kmText) { _, v in leg.distanceKm = EditorLogic.parseKm(v) }
        .onChange(of: minText) { _, v in leg.durationMinutes = EditorLogic.parseMinutes(v) }
    }
}

#Preview("Leg editor") {
    let container = AppContainer.make(inMemory: true)
    let journey = SampleData.mumbai(in: container.mainContext)
    return NavigationStack { LegEditorView(leg: journey.orderedLegs[0]) }
        .modelContainer(container)
}
