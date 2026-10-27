import SwiftUI

/// Copy for each state, shared by the shelf banner, the alert and the Settings tab.
enum SyncCopy {
    static let signedOutBanner = "Journeys stay on this device. Sign in to iCloud to sync."
    static let importing = "Bringing in your journeys from iCloud…"
    static let storageFullTitle = "iCloud storage is full"
    static let storageFullMessage = "New photos won't sync until space is freed in iCloud settings."

    static func settingsLine(for state: SyncState) -> String {
        switch state {
        case .disabled, .signedOut: signedOutBanner
        case .importingFirstTime: importing
        case .upToDate: "Your journeys sync through iCloud."
        case .storageFull: "iCloud storage is full. New photos won't sync until space is freed."
        }
    }
}

/// Small strip under the toolbar, shown only when signed out of iCloud on a build that can sync.
struct SyncBanner: View {
    static func isVisible(for state: SyncState) -> Bool { state == .signedOut }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.slash").accessibilityHidden(true)
            Text(SyncCopy.signedOutBanner)
        }
        .font(.footnote)
        .foregroundStyle(KraftColor.inkSoft)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(KraftColor.paperDeep)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("syncBanner")
    }
}

private struct SyncStatusPresentation: ViewModifier {
    @Environment(\.syncState) private var state
    @State private var showStorageFull = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if SyncBanner.isVisible(for: state) { SyncBanner() }
            }
            .alert(SyncCopy.storageFullTitle, isPresented: $showStorageFull) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(SyncCopy.storageFullMessage)
            }
            .onChange(of: state, initial: true) { _, new in
                if StorageFullAlertTracker().shouldPresent(for: new) { showStorageFull = true }
            }
    }
}

extension View {
    /// Adds the sync banner and the one-time storage-full alert. Does nothing while `\.syncState` is `.disabled`.
    func syncStatusPresentation() -> some View { modifier(SyncStatusPresentation()) }
}
