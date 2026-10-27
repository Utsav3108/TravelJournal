import SwiftUI

/// "All" plus one chip per city; `selection == nil` means All.
struct CoverRackChips: View {
    let cities: [LibraryCity]
    let total: Int
    let selection: String?
    let select: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: total, isOn: selection == nil) { select(nil) }
                ForEach(cities) { city in
                    chip(city.name, count: city.count, isOn: selection == city.name) { select(city.name) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ name: String, count: Int, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(name).font(.custom(KraftFontName.loraSemiBold, size: 15, relativeTo: .subheadline))
                Text("\(count)").font(.custom(KraftFontName.lora, size: 13, relativeTo: .footnote)).monospacedDigit()
                    .opacity(0.75)
            }
            .lineLimit(1)
            .foregroundStyle(isOn ? Color.white : CoverRackLibPalette.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(isOn ? CoverRackLibPalette.text : Color.white.opacity(0.65)))
            .overlay(Capsule().strokeBorder(CoverRackLibPalette.text.opacity(isOn ? 0 : 0.2), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue("\(count) \(count == 1 ? "story" : "stories")")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
