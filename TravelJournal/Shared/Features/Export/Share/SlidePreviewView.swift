import SwiftUI
import ImageIO

/// Which slide is showing, and the numbers the preview prints. Pure so it can be tested.
nonisolated struct SlidePager: Equatable {
    let count: Int
    private(set) var index: Int = 0

    init(count: Int, index: Int = 0) {
        self.count = max(0, count)
        self.index = 0
        select(index)
    }

    /// "3 / 12" (1-based); empty when there are no slides.
    var label: String { count == 0 ? "" : "\(index + 1) / \(count)" }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < count - 1 }

    mutating func select(_ i: Int) { index = count == 0 ? 0 : min(max(i, 0), count - 1) }
    mutating func next() { select(index + 1) }
    mutating func previous() { select(index - 1) }

    /// Width / height of one slide exactly as Instagram shows it: 4:5 carousel, 9:16 Story.
    static func aspectRatio(for format: ExportFormat) -> CGFloat {
        let s = format.spec.sliceSize
        return s.width / s.height
    }

    /// The largest slide of `aspect` that fits `container` (letterboxed, never cropped).
    static func fittedSize(aspect: CGFloat, in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0, aspect > 0 else { return .zero }
        let w = min(container.width, container.height * aspect)
        return CGSize(width: w, height: w / aspect)
    }
}

/// Preview of exported slides / frames before sharing or saving: swipe through them at Instagram's aspect
/// (paging `TabView` on iPhone, a pager with arrows and ←/→ keys on Mac), then Share (Instagram appears in the
/// share sheet when it's installed), Save to Photos (iPhone) or Save to Folder… (Mac).
struct SlidePreviewView: View {
    let images: [URL]
    let format: ExportFormat
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var pager: SlidePager
    @State private var saver = PhotosSaver()
    @State private var message: String?
    #if os(macOS)
    @State private var savingToFolder = false
    #endif

    init(images: [URL], format: ExportFormat, title: String) {
        self.images = images
        self.format = format
        self.title = title
        _pager = State(initialValue: SlidePager(count: images.count))
    }

    private var aspect: CGFloat { SlidePager.aspectRatio(for: format) }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            VStack(spacing: 12) {
                TabView(selection: Binding(get: { pager.index }, set: { pager.select($0) })) {
                    ForEach(images.indices, id: \.self) { i in
                        slide(i).padding(.horizontal, 16).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                pageLabel
                actions
            }
            .padding(.bottom, 12)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("slidePreviewDone")
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil; saver.reset() }
            }
        }
        #else
        VStack(spacing: 12) {
            HStack {
                Text(title).font(.headline).lineLimit(1)
                Spacer(minLength: 12)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("slidePreviewDone")
            }
            HStack(spacing: 12) {
                Button { pager.previous() } label: { Image(systemName: "chevron.left") }
                    .disabled(!pager.canGoBack)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityLabel("Previous slide")
                slide(pager.index)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    .id(pager.index)
                    .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                        if v.translation.width < 0 { pager.next() } else { pager.previous() }
                    })
                Button { pager.next() } label: { Image(systemName: "chevron.right") }
                    .disabled(!pager.canGoForward)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .accessibilityLabel("Next slide")
            }
            .buttonStyle(.borderless)
            .font(.title2)
            pageLabel
            actions
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
        #endif
    }

    // MARK: Pieces

    private func slide(_ i: Int) -> some View {
        GeometryReader { geo in
            let size = SlidePager.fittedSize(aspect: aspect, in: geo.size)
            SlideImage(url: images.indices.contains(i) ? images[i] : nil, label: "Slide \(i + 1) of \(images.count)")
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slide \(i + 1) of \(images.count)")
    }

    private var pageLabel: some View {
        Text(pager.label)
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("slidePreviewPage")
    }

    private var actions: some View {
        HStack(spacing: 12) {
            ShareLink(items: images) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("slidePreviewShare")
            #if os(iOS)
            Button {
                Task {
                    await saver.save(images)
                    message = saver.state.message
                }
            } label: {
                if saver.isSaving {
                    ProgressView()
                } else {
                    Label("Save to Photos", systemImage: "photo.badge.plus")
                }
            }
            .disabled(saver.isSaving)
            .accessibilityIdentifier("slidePreviewSavePhotos")
            #else
            Button {
                savingToFolder = true
                Task {
                    defer { savingToFolder = false }
                    do {
                        if let urls = try await FolderExporter.chooseFolderAndExport(images, title: title,
                                                                                       window: NSApp.keyWindow) {
                            message = "Saved \(urls.count) slide\(urls.count == 1 ? "" : "s")."
                        }
                    } catch {
                        message = error.localizedDescription
                    }
                }
            } label: {
                Label("Save to Folder…", systemImage: "folder")
            }
            .disabled(savingToFolder)
            .accessibilityIdentifier("slidePreviewSaveFolder")
            #endif
        }
        .buttonStyle(.bordered)
        .disabled(images.isEmpty)
    }
}

/// One slide JPEG, decoded off the main thread at a preview size.
private struct SlideImage: View {
    let url: URL?
    let label: String
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            if let image {
                Image(image, scale: 1, label: Text(label)).resizable().interpolation(.high)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached(priority: .userInitiated) { Self.decode(url, maxPixel: 1400) }.value
        }
    }

    nonisolated static func decode(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

#Preview {
    SlidePreviewView(images: [], format: .carousel, title: "A Day in Mumbai")
}
