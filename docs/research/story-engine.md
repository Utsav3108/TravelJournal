# L3 Research: Story engine, Map and PDF

Deployment target in project: iOS 27.0 (Xcode template value), so iOS 17+/18+ APIs (ScrollView paging, `@Observable`, `MapKit` modern APIs, `ImageRenderer`) are all available without `#available`. Decisions from PLAN.md assumed: A4 only, Mood/Tip cut, 100 words per stop so one stop = one page, no text pagination.

## 1. One layout engine, two renderers

Pipeline: `Journey (SwiftData) -> JourneySnapshot (plain structs) -> StoryLayout.pages(snapshot) -> [StoryPage] -> StoryPageView(page, metrics)`.
Keep SwiftData `@Model` objects out of the engine; map to Sendable value types first (also needed because PDF export reads photos off-disk).

```swift
enum StoryPage: Identifiable, Hashable {
    case cover(CoverModel)
    case routeOverview(OverviewModel)        // map image + stats + pin list
    case stop(StopPageModel)                 // template, seeded rotations, route in/out
    case closing(ClosingModel)
    var id: String { /* "cover", "stop-<uuid>", ... */ }
}
struct StopPageModel: Hashable {
    let stopID: UUID; let index: Int; let template: StopTemplate // by photo count 0...4
    let entry: PageEdge; let exit: PageEdge         // .left/.right/.top/.bottom, alternates by index
    let seed: UInt64                                  // hash(stopID) -> rotations, tape colours
    let inLeg: LegModel?; let outLeg: LegModel?       // the connector belongs to BOTH adjacent pages
}
struct PageMetrics { var size: CGSize; var margin: CGFloat; var scale: CGFloat }  // phone: 24pt, A4: 36pt
```

Leg connectors are NOT separate pages (spec order lists them between stops but one stop = one page and the route must cross the boundary). Model them as data on the stop pages: page N draws the outgoing stroke from its anchor to its `exit` edge point; page N+1 draws the incoming stroke from its `entry` edge to its anchor. Rule: exit side of N == opposite side of entry of N+1, at the same normalized coordinate (e.g. `exit = .right @ y=0.62`; next `entry = .left @ y=0.62`). Store the edge crossing as normalized `CGPoint` in the model so both pages agree; a pure function `RouteGeometry.edgeY(legIndex)` seeded by leg id guarantees this.

Rendering: `StoryPageView` reads an `@Environment(\.pageMetrics)`. All sizes are expressed as `metrics.u(x)` or `x * scale`. Phone: page size = container proposed size (aspect forced to 595:842 so layout is identical and just scaled), PDF: 595x842 at scale 1. Simplest robust approach: author every page at a fixed design canvas of 595x842, wrap in `.frame(width: 595, height: 842)`, and on phone apply `.scaleEffect(fit)` inside a `GeometryReader` (or `.visualEffect`). This yields exact parity and zero re-layout logic; cost: text is scaled with the page (acceptable, it is a scrapbook; Dynamic Type deliberately not applied to story pages). Margin env still differs (24pt phone vs 36pt PDF) only if you author in phone-size canvas; recommended: author at A4 canvas with 36pt margins and accept the phone sees them scaled (~0.65x gives about 23pt, matching the 24pt goal nicely). That removes the two-metrics problem.

Connector across boundary:
- Horizontal pager: draw a short "stub" on each page. For continuity while swiping, draw a duplicate dash segment overshooting the page edge by ~0 (clip at page edge); the dash phase must match: set `dashPhase` so that the pattern at the exit edge on N equals pattern at entry on N+1 (compute path length L_N from anchor to edge; next page's phase = -(L_N mod period)... simplest: start next stroke with phase 0 and end previous at a whole number of periods by trimming `trim(from:0,to:)` to a multiple of period). Page-flip scroll shows both pages side by side during drag only if `ScrollView` paging uses `.scrollTargetBehavior(.paging)` with zero spacing, so the stubs visually meet.
- PDF: pages are separate; stubs just touch the page edge (printed spread alignment is not guaranteed). Add a small arrowhead at the exit and "continues" icon with leg label so the connector reads on its own. Leg note card sits beside the exit stub (spec: leg story prints as small note card). In-app, the same card is hidden (`metrics.mode == .interactive`) and appears as a popup on tap. Keep this one conditional in the page view; everything else identical.

## 2. Viewer interactions (in-app only)

- Paging: `ScrollView(.horizontal) { LazyHStack(spacing: 0) { ForEach(pages) { StoryPageView($0).containerRelativeFrame(.horizontal) } } }.scrollTargetBehavior(.paging).scrollPosition(id: $currentPageID)`. Preferred over `TabView(.page)`: programmatic jump is `withAnimation { currentPageID = stopPageID }`, keeps dots out, and gestures on child content (drag-on-photo) are friendlier. `TabView(.page)` is fine fallback but its tag-selection animation is flaky with lazy content.
- Pin tap on overview: overlay `Button` per pin at `pointInView = snapshotPoint * (viewSize / snapshotSize)`, action sets `currentPageID = .stop(id)`. Pin buttons need min 44pt hit area (`.contentShape(Circle().inset(by:-12))`).
- Route segment hit-testing. Dashed 2-3pt lines are hard to hit; build a hit path separately from the drawing: per leg, an invisible stroke with `lineWidth: 28`. Two options:
  1. `Path.strokedPath(StrokeStyle(lineWidth: 28))` + `.contentShape(thatPath)` + `.onTapGesture` on a transparent overlay (one view per leg; SwiftUI does the hit testing, no math). Note `.contentShape` accepts any Shape; wrap path in a `Shape` struct. Do not dash it (dashes create gaps).
  2. Manual: on a single `SpatialTapGesture`, compute distance from the tap to each segment (clamped projection) and choose min < 22pt. Needed if segment is a curve: flatten to polyline first. Option 1 is simpler; use option 2 only for the map snapshot where the line is drawn into a bitmap (not a view) and you must hit-test in view coords anyway; then also option 1 works with polyline paths built from `snapshot.point(for:)`.
- Leg card: `.popover`/custom overlay card with matchedGeometry optional; sheet with `.presentationDetents([.medium])` is least fragile.
- Photo full screen: `.fullScreenCover(item:)` with zoomable image; `matchedTransitionSource` / `.navigationTransition(.zoom)` is nice-to-have.
- Edit button: toolbar/overlay button -> `onEdit(stopID)`; viewer must refresh because pages derive from SwiftData `@Query`: rebuild `[StoryPage]` in a computed property on `.onChange` of journey (or via `@Query` update).
- Interaction layer lives in the viewer wrapper, not in `StoryPageView`; pages take closures (`onPhotoTap`, `onPinTap`, `onLegTap`) that are `nil` in PDF mode. Hit-test overlays are omitted from PDF.

## 3. Overview map

Snapshot (async, off main work happens inside MapKit):
```swift
func makeSnapshot(coords: [CLLocationCoordinate2D], size: CGSize) async throws -> MapSnap {
    let o = MKMapSnapshotter.Options()
    o.region = MKCoordinateRegion(fitting: coords, paddingFactor: 1.5)   // own helper: bbox*1.5, min span 0.01 deg
    o.size = size                          // A4 map card e.g. 523x340 (595-2*36)
    o.scale = 3                            // do not use UIScreen.main; fixed 3 for sharp PDF, 2 for phone cache
    o.mapType = .mutedStandard; o.showsBuildings = false
    o.pointOfInterestFilter = .excludingAll; o.traitCollection = .init(userInterfaceStyle: .light)
    let snap = try await MKMapSnapshotter(options: o).start()
    let pts = coords.map { snap.point(for: $0) }                       // in snapshot POINT space (size), not pixels
    return MapSnap(image: tinted(snap.image), points: pts)
}
```
- Region fitting: prefer `o.mapRect` computed from `MKMapRect` union of `MKMapPoint`s, inset with `.insetBy(dx: -w*0.25, dy: -h*0.25)`, then expand to the card aspect ratio (snapshotter otherwise letterboxes by changing the visible rect, so `snap.point(for:)` stays correct either way; always use it rather than your own projection). Single stop: min span; 0 located stops: skip the map page entirely or show a "no locations" paper card.
- Stops without location: filter before building coords but keep their stop index for pin numbers (pin number = stop order, so numbers can skip: 1,3,4). Route line connects only located consecutive stops; mark the gap with a dashed "?" hop or simply bridge.
- Sepia/paper treatment: `CIFilter.sepiaTone` (intensity 0.8) then `CIColorControls` (saturation 0.6, contrast 0.9), or `CIColorMonochrome` with kraft color (`inputColor` 0.55,0.42,0.28; intensity 0.9) which gives better control of the hue; blend with `CIMultiplyBlendMode` over a paper texture/grain image (cropped to extent), plus a vignette (`CIVignette`). Do this on a `CIContext` created once (reuse; creation is costly) and return `UIImage(cgImage:)`. Keep it a function `Image -> Image` so PDF and viewer share it.
- Overlays (route, pins) are drawn as SwiftUI views over the tinted image using `points` (scale = viewSize/snapshotSize), NOT baked into the bitmap: vector in PDF, tappable in app. Pins: numbered circle stamps in `Canvas` or `ZStack` with `.position`. Route: `Path` through points, dashed stroke `lineCap .round`, optional gentle quadratic curve per leg (control point offset perpendicular seeded by leg id); hit shape uses the same Path.
- Offline caveat: `MKMapSnapshotter` needs network for tiles (no offline maps API). Fail path: catch error and render a paper "illustrated" fallback (grid/graph paper background, pins at normalized bbox positions via linear mapping). Cache the produced PNG to disk keyed by hash(coords, size) so a PDF can be exported offline once the viewer has loaded it once; invalidate when stops change. Snapshotter may also deliver partially empty tiles when throttled; test on device. Also set a 10s timeout (`Task` + `withTimeout`).
- Stats strip (pure function over snapshot): stops = count; km = sum of leg.distance (nil counted 0; if all nil, show "-" or omit); minutes = sum leg.duration (+ optionally stop time spent for "day length"; spec example "5 h 20 min" ambiguous, decide: legs + stop dwell time, label clearly); modes = distinct leg modes by frequency, "walk, taxi". Format with `Duration`/manual "h m"; `Measurement(...).formatted(.measurement(width:.abbreviated))` for km locale (miles in US locale is a decision; keep km as spec).

## 4. PDF export

Recommended, as tested in the spike (PDFSpike.swift, ran on macOS):
```swift
@MainActor func exportPDF(pages: [StoryPage], to url: URL) {
    var box = CGRect(x:0,y:0,width:595,height:842)
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: title] as CFDictionary) else { return }
    for p in pages {
        let r = ImageRenderer(content: StoryPageView(page: p, metrics: .a4).environment(\.renderMode, .pdf))
        r.proposedSize = .init(width: 595, height: 842)
        r.render { _, draw in ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage() }
    }
    ctx.closePDF()
}
```
- Findings from the spike: result is a valid 2-page PDF, MediaBox 595x842, text stays vector with subsetted TrueType fonts embedded (SF/New York embedded as subsets; custom bundled TTF/OTF also embed as subsets), dashed stroke is vector, `rotationEffect` works, orientation upright (no manual flip needed with `render`'s closure, it applies the correct transform for the context). Spike file size: 14 KB for 2 text pages.
- Pitfalls: `render` must be called on the main actor; its closure is synchronous, so everything must be ready beforehand: preload photos as `UIImage`/`Image(uiImage:)` and the map snapshot before calling (no `AsyncImage`, no `.task` loading, no PhotosPicker items). Views using `.task`/`onAppear` to load will render empty. Use a `PreparedAssets` struct (dict of id -> UIImage downsampled) passed into the page models.
- UIGraphicsPDFRenderer alternative: `UIGraphicsPDFRenderer(bounds:).writePDF(to:) { ctx in ctx.beginPage(); render {_, draw in draw(ctx.cgContext)} }` works too, and handles page flipping; but the CGContext path avoids UIKit dependency and one level of nesting. Either is fine. Do NOT use `ImageRenderer.uiImage` (rasterizes, loses vector).
- Rasterized parts: images are embedded as images (JPEG/Flate chosen by CG); effects like `.blur`, `.shadow` with blur radius, `.blendMode`, `.colorMultiply`/`.compositingGroup`, `.mask`, materials, and `Canvas` blend can force rasterization of that layer or be dropped/differ. Shadows on photos rasterize at low resolution in some cases; check zoomed output. Grain overlay: use a tiled PNG at reduced opacity; blend modes (`.multiply`) in PDF viewers are supported but verify in Preview and Files QuickLook.
- Size: embed photos downsampled to ~1600px long edge (A4 at 150-200dpi, polaroids cover ~half page) before render. JPEG q 0.75 about 250-400 KB each; 4 photos x N stops. A 6-stop day with 4 photos each = 24 photos is about 6-10 MB. Large originals (12 MP) embedded raw yield 50+ MB; avoid by downsampling with `CGImageSourceCreateThumbnailAtIndex` (kCGImageSourceThumbnailMaxPixelSize). Note: CG may re-encode images as Flate rather than DCT in some paths, inflating size; if the spike with real photos shows this, pass pre-compressed JPEG-backed `CGImage` (created from JPEG data via `CGImage(jpegDataProviderSource:)`) which CG embeds as DCT passthrough. Must verify on device (not tested here: spike has no photos).
- Writing: `FileManager.default.temporaryDirectory.appending(path: "A Day in Mumbai.pdf")`; delete after share. Filename = sanitized title.
- Sharing: `ShareLink(item: url)` (URL of the file; use `Transferable` with `FileRepresentation` only if lazily generating) in the viewer toolbar after generation completes; show a progress indicator while rendering (rendering 8-10 pages on main actor blocks UI about 1-3 s; yield between pages with `await Task.yield()`). Share sheet offers "Save to Files", AirDrop, Print. Alternative `.fileExporter` with `FileDocument` to write directly to Files. Prefer ShareLink.
- Fonts: bundled fonts (Allura/Lora/Caveat/Special Elite) are embedded as subsets automatically if registered via `UIAppFonts` and used by name `Font.custom`. Make sure Font.custom sizes are fixed (`.custom(name, fixedSize:)`) so Dynamic Type does not alter PDF.

## 5. Parity pitfalls (in-app vs PDF)

- Dynamic Type: the page canvas must ignore it. Use `Font.custom(_, fixedSize:)` and `.dynamicTypeSize(.large)` on the root of `StoryPageView` (also in the renderer: ImageRenderer inherits environment defaults from the device's current setting, not the app UI, so pin it explicitly). Provide a Larger-text alternative elsewhere (accessibility labels) rather than in the page.
- Safe areas: ImageRenderer has no safe area; in-app pager must `ignoresSafeArea` for the paper background but keep content within A4 margins via the canvas scale. Do not use `GeometryReader` global frames or `safeAreaInset` inside pages.
- Colour scheme: force `.preferredColorScheme(.light)` / `.environment(\.colorScheme, .light)` on pages and in the renderer; the renderer otherwise uses the current system scheme. Also set `\.displayScale = 3`, `\.locale`, `\.layoutDirection`.
- Determinism: seed all rotations/tape picks from `stopID` hash via a custom `SplitMix64` (not `Hasher`/`.hashValue`, which is randomized per launch). Never use `.random`, `Date()`, or `UUID()` inside body.
- No animation/transitions in render: gate with `metrics.mode`; disable `.animation`, `withAnimation`, `matchedGeometry`, `.transition`, `Canvas` timelines. Use `.transaction { $0.animation = nil }` at the root. Avoid `ScrollView`/`List`/`TextEditor`/`Map`/`UIViewRepresentable` in page views: ImageRenderer does not draw them (shows placeholder yellow/red marks). Map is already an image.
- Lazy/offscreen: pager uses LazyHStack, so the interactive path only builds visible pages; PDF builds each page fresh, so do not share @State.
- Text fit: 100-word cap fits the note card at design size; still use `.minimumScaleFactor(0.85)` and `.lineLimit` as safety net and unit test with the longest allowed text (CJK/Devanagari fonts have taller line height; Special Elite lacks Devanagari glyphs, so fall back via system font cascade and test "Mumbai" Marathi/Hindi text).
- Snapshot tests: render each page via `ImageRenderer` to PNG at scale 1 in XCTest, compare phone-scaled vs A4 (parity = identical bitmaps at same scale since same canvas).
- Wrong dpi/scale: ImageRenderer `scale` only affects rasterization in `.uiImage`/`.cgImage`; PDF path is in points.

## 6. Spike

`docs/research/spikes/PDFSpike.swift`: standalone macOS SwiftUI script, 2 A4 pages with kraft background, serif title, tilted note, dashed Bezier. Compiled with `swiftc -parse-as-library` (Swift 6.4, macOS 27 SDK) and RAN: output `file`: PDF 1.3, 2 pages, MediaBox 595x842, 13.9 KB, embedded font subset `AAAAAB+.NewYork-Regular`, rendered upright, verified via Quick Look thumbnail. NOT tested: iOS device, custom fonts, photos, map snapshot, blend modes. See `spikes/NOTES.md`.

## Open risks

1. Photo embedding size/format in PDF (Flate vs DCT) not measured; need on-device spike with 24 real photos.
2. Blur/shadow/blend-mode/mask effects rasterise or drop in PDF; limit these in the design system or test each.
3. MKMapSnapshotter needs network; offline export relies on cache; fallback illustration needs design.
4. Scale-a-fixed-A4-canvas approach makes phone text small (~0.65x): 16pt body -> about 10pt; verify legibility, or raise phone body font in the design (D2 to decide).
5. `ImageRenderer` main-actor cost: long journeys may block UI 2-5 s; needs progress UI and page-by-page yielding.
6. Dashed route phase continuity across pages is approximate; depends on exact edge-point sharing.
7. Hit-testing a stroked dashed path via `contentShape` needs a separate non-dashed hit shape; map-snapshot variant needs verification of point scaling.
8. Total-time stat definition (legs only vs legs+dwell) not defined by the spec.
9. Deployment target 27.0 is the Xcode default for this SDK; confirm it is intended, it restricts devices.
