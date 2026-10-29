#if os(macOS)
import SwiftUI
import AppKit

/// The hold-to-speak card pinned to the bottom of the sidebar (design_handoff_hold_to_text, section A).
struct VoiceCardView: View {
    let controller: VoiceDictationController
    let stop: Stop
    let number: Int
    let press: () -> Void
    let release: () -> Void

    private var isNew: Bool { VoiceDraftApplier.isNewStop(placeName: stop.placeName, story: stop.story) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isNew ? "NEW STOP · SAY WHERE YOU WERE" : "SPEAK INTO STOP \(number)")
                .font(.system(size: 11, weight: .semibold)).tracking(0.44)
                .foregroundStyle(KraftColor.inkSoft)
            Text(stop.placeName.isEmpty ? "New stop" : stop.placeName)
                .font(KraftFont.stopName(26)).foregroundStyle(KraftColor.ink)
                .lineLimit(1).truncationMode(.tail)
            content
            VoiceHoldButton(phase: controller.phase, press: press, release: release)
            HStack(spacing: 4) {
                Text("or hold")
                Text("space")
                    .font(.system(size: 10))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(KraftColor.inkSoft.opacity(0.35), lineWidth: 1))
            }
            .font(.system(size: 11)).foregroundStyle(KraftColor.kraftDark)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(KraftColor.voiceCard))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(KraftColor.kraftDark.opacity(0.2), lineWidth: 1))
        .padding(10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voiceCard")
    }

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .idle:
            note(idleCopy)
        case .listening, .processing:
            ScrollView {
                Text(controller.transcript.isEmpty ? "…" : controller.transcript)
                    .font(KraftFont.bodyItalic(13.5)).foregroundStyle(KraftColor.kraftDark)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)   // keep the newest words in view
            .frame(maxHeight: 120)
            .fixedSize(horizontal: false, vertical: true)
        case .filled(let fields):
            VStack(alignment: .leading, spacing: 8) {
                note("Filled in")
                FlowLayout(spacing: 5) {
                    ForEach(fields, id: \.self) { f in
                        Text(f.label).font(.system(size: 11.5))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(KraftColor.kraft.opacity(0.45)))
                    }
                }
                HStack(spacing: 14) {
                    Button("Undo", action: controller.undo).foregroundStyle(KraftColor.route)
                        .accessibilityIdentifier("voiceUndo")
                    Button("Looks right", action: controller.dismiss).foregroundStyle(KraftColor.inkSoft)
                        .accessibilityIdentifier("voiceDismiss")
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 6) {
                note(error.message)
                if error.offersSettings {
                    Button("Open Settings", action: openPrivacySettings)
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KraftColor.route)
                }
            }
        }
    }

    private var idleCopy: String {
        if isNew { return "Say the place, when you got there and what it was like. Everything on the right fills in." }
        if !stop.story.isEmpty { return "Talk to add more. Mentions of time, money, stars or how you got there go to the right field." }
        return "Just talk about it. Story, rating, cost and travel fill in on the right."
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(KraftColor.inkSoft)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The pill: idle / listening (pulsing ring, moving bars) / processing.
private struct VoiceHoldButton: View {
    let phase: VoiceDictationController.Phase
    let press: () -> Void
    let release: () -> Void

    @State private var held = false
    @State private var animating = false

    private var listening: Bool { phase == .listening }
    private var processing: Bool { phase == .processing }

    var body: some View {
        ZStack {
            if listening {
                Capsule().fill(KraftColor.route)
                    .scaleEffect(animating ? 1.5 : 1).opacity(animating ? 0 : 0.45)
                    .animation(.easeOut(duration: 1.3).repeatForever(autoreverses: false), value: animating)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 8) {
                bars
                Text(label).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(KraftColor.paper)
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(Capsule().fill(fill))
            .animation(.easeOut(duration: 0.2), value: phase)
        }
        .contentShape(Capsule())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !held { held = true; press() } }
            .onEnded { _ in if held { held = false; release() } })
        .onChange(of: listening) { _, on in animating = on }
        .accessibilityElement()
        .accessibilityLabel("Hold to speak")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("voiceHoldButton")
    }

    private var label: String {
        if listening { return "Listening… let go to finish" }
        if processing { return "Writing it down…" }
        return "Hold to speak"
    }

    private var fill: Color {
        if listening { return KraftColor.routePressed }
        if processing { return KraftColor.kraftDark }
        return KraftColor.route
    }

    private var bars: some View {
        let rest: [CGFloat] = [0.4, 0.75, 1, 0.75, 0.4]
        return HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { k in
                Capsule().fill(KraftColor.paper).frame(width: 2.5, height: 14)
                    .scaleEffect(y: listening ? (animating ? 1 : 0.3) : rest[k])
                    .animation(listening ? .easeInOut(duration: 0.9).repeatForever().delay(Double(k) * 0.12) : .default,
                               value: animating)
            }
        }
    }
}

/// Wraps chips onto new lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
#endif
