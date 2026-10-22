import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Shown instead of the app when the data store can't be opened. No model container is attached while this is on
/// screen, so nothing can display (or write to) an empty stand-in for the user's real data.
struct StoreFailureView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Something went wrong")
                .font(.title2.weight(.semibold))
            Text("Please close and reopen TravelJournal. If it keeps happening, restart your device and try again. Your journeys have not been changed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Try again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                #if os(macOS)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                #endif
            }
        }
        .padding(32)
        .frame(maxWidth: 420, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.96))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storeFailure")
    }
}

#Preview {
    StoreFailureView(onRetry: {})
}
