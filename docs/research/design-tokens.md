# D1 Design Tokens: Vintage Kraft foundations

Sources: spec pages 6-8 (colour, type, assets, layout), style target `images/3.png` (Japan kraft spread). Project facts (from `project.pbxproj`): `objectVersion = 110`, three `PBXFileSystemSynchronizedRootGroup`s (app, tests, UI tests), `GENERATE_INFOPLIST_FILE = YES`, no custom Info.plist, deployment target iOS 27.0. Fonts were not downloaded; PostScript names below are from memory of the Google Fonts files and MUST be verified (see Open risks).

## 1. Colour tokens

Prefer code-defined colours (no asset-catalog round trip, identical in app and `ImageRenderer` PDF, no appearance trait surprises).

```swift
// DesignSystem/Tokens/KraftColor.swift
import SwiftUI
extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF)/255, green: Double((hex >> 8) & 0xFF)/255,
                  blue: Double(hex & 0xFF)/255, opacity: opacity)
    }
}
enum KraftColor {
    static let paper      = Color(hex: 0xF3EBDD) // page + app bg
    static let paperDeep  = Color(hex: 0xE6D9C3) // cards on paper
    static let kraft      = Color(hex: 0xC9A97E) // kraft cards, ticket stubs, tape
    static let kraftDark  = Color(hex: 0x8B6B4A) // borders, stamp outlines
    static let ink        = Color(hex: 0x2B2420) // primary text
    static let inkSoft    = Color(hex: 0x5E5249) // secondary text, captions
    static let route      = Color(hex: 0x9E3B2F) // dashed route, arrows, pins
    static let sealRose   = Color(hex: 0xB5838D) // wax seal, hearts, accent buttons
    static let stampTeal  = Color(hex: 0x3E6B6A) // postmarks, category stamps
    static let highlight  = Color(hex: 0xF2D06B, opacity: 0.70) // highlighter strips
}
```

Extra derived tokens (not in spec; keep few): `shadow = ink.opacity(0.18)` (polaroid/card drop shadow), `paperEdge = kraftDark.opacity(0.35)` (hairline on torn edges). Use `.multiply` blend for highlight over text-bearing paper so ink stays dark.

Contrast: ink on paper ~14:1, inkSoft on paper ~6.5:1 (AA), route on paper ~5.5:1 (AA), stampTeal on paper ~4.9:1 (OK for 11pt uppercase stamps only if bold-ish; keep stamps decorative with labels also in accessibility text). sealRose on paper is decorative only (~2.6:1); do not put text on it.

Dark mode stance:
- Story pages (cover, overview, stop pages, closing) and the PDF are paper-coloured always. They are an artefact, like a printed page. Apply `.environment(\.colorScheme, .light)` on the story viewer subtree, and ensure the PDF renderer sets the same.
- Editor and shelf screens: calm cream (`paper` bg, `ink` text, system controls). v1 recommendation: force light appearance app-wide (`UIUserInterfaceStyle = Light` via `INFOPLIST_KEY_UIUserInterfaceStyle = Light` in build settings) because the theme only defines light values. Revisit in v1.1 with a dark editor palette (`paperDark #211C18`, `inkOnDark #EFE6D6`) while leaving story pages light.
- `AccentColor` asset: set to `route` or `sealRose` (spec: accent buttons = sealRose); tint system controls via `.tint(KraftColor.sealRose)`. White text on sealRose is below AA, so use `ink` label on rose buttons or use `route` for primary buttons with `paper` label.

## 2. Fonts

| Role | Family | Google Fonts page | Licence | Download (when ready) |
|---|---|---|---|---|
| Title/stop name | Allura | https://fonts.google.com/specimen/Allura | OFL 1.1 | `https://fonts.google.com/download?family=Allura` or raw `https://github.com/google/fonts/tree/main/ofl/allura` |
| Body | Lora | https://fonts.google.com/specimen/Lora | OFL 1.1 | `.../download?family=Lora`, repo dir `ofl/lora` |
| Annotations | Caveat | https://fonts.google.com/specimen/Caveat | OFL 1.1 | `.../download?family=Caveat`, repo dir `ofl/caveat` |
| Labels/stamps | Special Elite | https://fonts.google.com/specimen/Special+Elite | Apache 2.0 per google/fonts repo (`apache/specialelite`), NOT OFL; spec says "all OFL", correct it | `.../download?family=Special+Elite`, repo dir `apache/specialelite` |

Files to bundle (minimum set) and expected PostScript names (verify with `fc-scan --format '%{postscriptname}\n' file` or Font Book):
- `Allura-Regular.ttf` -> `Allura-Regular`
- `Lora-Regular.ttf` -> `Lora-Regular`; `Lora-Italic.ttf` -> `Lora-Italic`; optional `Lora-SemiBold.ttf` -> `Lora-SemiBold`
- `Caveat-Regular.ttf` -> `Caveat-Regular`; optional `Caveat-Bold.ttf` -> `Caveat-Bold`
- `SpecialElite-Regular.ttf` -> `SpecialElite-Regular`

Google's zip ships Lora and Caveat as variable fonts (`Lora[wght].ttf`, `Caveat[wght].ttf`) plus a `static/` folder. Use the `static/` files: `Font.custom` against variable fonts only reliably reaches the default instance and named-instance PS names are fiddly. Ship OFL.txt / licence texts for each in `Resources/Fonts/LICENSES/` (OFL requires the licence + copyright text to travel with the font; the licences folder must NOT be added to Copy Bundle Resources by name collision, see below). Add a Settings/About "Acknowledgements" line.

### Registration for this project

The app group is a synchronized folder, so any file dropped under `TravelJournal/` is automatically added to the target and, for non-source files, copied to the bundle root (flattened). There is no `Info.plist` and `GENERATE_INFOPLIST_FILE = YES`; `UIAppFonts` (an array) has no `INFOPLIST_KEY_` equivalent. Two options:

1. Recommended: register at launch with CoreText. No plist edit, no pbxproj edit, works in previews and in the test host.
```swift
// DesignSystem/Typography/FontRegistrar.swift
import CoreText, Foundation
enum FontRegistrar {
    static func registerAll() {
        let files = ["Allura-Regular","Lora-Regular","Lora-Italic","Lora-SemiBold",
                     "Caveat-Regular","Caveat-Bold","SpecialElite-Regular"]
        for f in files {
            guard let url = Bundle.main.url(forResource: f, withExtension: "ttf") else { assertionFailure("missing \(f)"); continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
// TravelJournalApp.init(): FontRegistrar.registerAll()   // must run before first view body
```
   Previews: call `registerAll()` from a preview helper too (previews run the app target, but `init` may not run).
2. Alternative: add `TravelJournal/Info.plist` containing `UIAppFonts` and set build setting `INFOPLIST_FILE`; it merges with generated keys. Because the folder is synchronized, Xcode will also try to copy Info.plist as a resource: add a `PBXFileSystemSynchronizedBuildFileExceptionSet` (Xcode: select file, Target Membership, untick) or keep the plist outside the synchronized folder (e.g. `Config/Info.plist`). More moving parts; prefer option 1.

Keep font files in `TravelJournal/DesignSystem/Resources/Fonts/` (synchronized, no pbxproj edit). Beware duplicate basenames across folders: the copy flattens, so avoid two `OFL.txt` files; name licences `Allura-OFL.txt`, etc., or keep them outside the target (e.g. repo `Licenses/`) and surface text via an Acknowledgements screen.

### Type scale and Dynamic Type

```swift
enum KraftFont {
    static func title(_ s: CGFloat = 44)  -> Font { .custom("Allura-Regular", size: s, relativeTo: .largeTitle) }
    static func stopName(_ s: CGFloat = 30) -> Font { .custom("Allura-Regular", size: s, relativeTo: .title) }
    static func body(_ s: CGFloat = 16)   -> Font { .custom("Lora-Regular", size: s, relativeTo: .body) }
    static func note(_ s: CGFloat = 18)   -> Font { .custom("Caveat-Regular", size: s, relativeTo: .callout) }
    static func label(_ s: CGFloat = 11)  -> Font { .custom("SpecialElite-Regular", size: s, relativeTo: .caption) }
}
extension View {
    func stampLabel() -> some View { self.font(KraftFont.label()).textCase(.uppercase).tracking(1.5) }
    func storyBody() -> some View { self.font(KraftFont.body()).lineSpacing(8) } // 24pt line height: 16pt Lora has ~21pt natural leading, so verify; lineSpacing = 24 - natural
}
```
- `Font.custom(_:size:relativeTo:)` scales with Dynamic Type automatically (iOS 14+). Use it for the editor's previews and in-app story if we want accessibility sizing; but story page layout is fixed-geometry (rotated polaroids, 100-word note card), so cap with `.dynamicTypeSize(...DynamicTypeSize.xLarge)` on story pages and keep full scaling on editor/system UI (SF Pro, system styles).
- PDF: the exporter must not depend on device settings. Wrap the PDF page view in `.environment(\.dynamicTypeSize, .large)` and use `@ScaledMetric`-free fixed sizes; `ImageRenderer` uses the environment of the supplied view, so set it explicitly. For fixed sizes without scaling use `.custom("Lora-Regular", fixedSize: 16)`.
- Allura is thin; below ~26pt it gets illegible: never use for body. Caveat at 18pt reads small, check 20pt on 3x. Special Elite caps + 1.5 tracking at 11pt is the spec; do not drop below 10pt.
- Missing-font fallback: `Font.custom` silently falls back to system, so add a debug assertion `UIFont(name:size:) != nil` in `registerAll`.

## 3. Asset inventory and recommendation

Rule of thumb: vector things with flat shape = SwiftUI `Shape`/`Canvas` (resolution independent, PDF stays vector, seeded variation possible). Organic/textured = raster PNG/JPEG in `Assets.xcassets` at @2x/@3x (PDF will embed bitmap; acceptable at ~300 dpi equivalent). Line icons = PDF/SVG single-scale vector in the asset catalog ("Preserve Vector Data" on) or SF Symbols-style custom symbol.

| Asset | Recommendation | Notes / sourcing |
|---|---|---|
| Paper grain (tileable) | PNG, 512x512 tile (tileable, ~20-60 KB, greyscale alpha, `.multiply`/overlay at ~8%); use `Image("paperGrain").resizable(resizingMode: .tile)` | Generate in-house: noise (Core Image `CIRandomGenerator` -> blur -> tint) or Python/Photoshop; zero licence risk. Do not bake tint; apply over `KraftColor.paper`. |
| Torn-edge masks x3 | Draw in code: `TornEdgeShape(seed:)` that jitters a rect path (random walk, amplitude 1.5-3pt, fibre-ish step 3-6pt) with 3 preset seeds/amplitudes. Add subtle white fibre stroke on top | Code gives a vector mask, matches in PDF, and per-element variation from seeded RNG. Fallback only if it looks too synthetic: 3 PNG alpha masks (resizable 9-slice). |
| Washi tape x3 | Code: rotated rounded rect with serrated ends (`WashiShape`), semi-transparent (0.85), fill variants: kraft (paper-grain overlay), pink grid (`Canvas` grid lines on `sealRose` tint), floral (small repeated petal glyphs; or PNG tile if petals look poor) | Floral is the one candidate for raster tile (draw 5-petal motif in a vector `Path` first). Keep each tape under ~30 lines. |
| Polaroid frame | Code: `Rectangle` paper-white (`#FBF7EE`), thicker bottom (approx 14% sides, 28% bottom), soft double shadow | Pure SwiftUI, scales to PDF. |
| Postage-stamp frame | Code: perforated edge via a `Shape` that subtracts circles along the edges (`even-odd` fill) | Pure SwiftUI. |
| Round postmark | Code: circle strokes + text on a circular path (needs custom `Canvas`/`Text` rotated per glyph, or `UIBezierPath` text) + wavy cancellation lines; content from data (date, city, stop number); `stampTeal` with `.multiply` and ~0.85 opacity, plus grain mask for ink wear | Data-driven so it MUST be code. Per-glyph arc layout helper is the only non-trivial bit (budget 1 day). |
| Wax seal | Vector or PNG: radial-gradient blob (irregular circle `Shape`) in `sealRose` + inner embossed ring + highlight; centre glyph (flower/initial) | Code is feasible (gradient + inner shadow), keep one `WaxSeal` view; fallback 1 PNG @3x if flat. |
| Paper clip | Vector PDF/SVG in Assets (single path, grey-metal stroke) or `Path` code | Simple; code is fine. |
| 6 category stamp icons (food, landmark, temple, stay, shopping, nature; plus `other` per spec's 7th category) | Vector PDF in Assets.xcassets (template rendering, tinted `stampTeal`), drawn inside a circular/rounded stamp frame in code | Note: spec's category list has 7 values (adds "other"); inventory says 6 icons, so `other` needs a 7th generic icon (or reuse a pin glyph). Source: draw in Figma/Affinity Designer, or Phosphor/Lucide icon sets (MIT/ISC) or Noun Project (check licence per icon; attribution needed on free tier). Avoid SF Symbols in the PDF-export path only if Apple licence matters for embedding (SF Symbols are OK in apps; not as standalone assets). |
| 8 transport icons (walk, auto-rickshaw, taxi, bus, train, metro, bike, ferry) | Vector PDF in asset catalog, single-colour line style, template rendering, 24-32pt grid, uniform 1.5pt stroke | Walk/bus/train/metro/bike/ferry exist in Lucide/Phosphor/Tabler (MIT-ish; keep licence file); auto-rickshaw is rare: draw custom (needed for Mumbai). Keep all 8 in one style: consider hand-redrawing all in one stroke width to match "ink-line style". SF Symbols (`figure.walk`, `bus`, `tram.fill`, `bicycle`, `ferry`) are inconsistent and not styled, so do not use. |

Resolution/PDF notes: `ImageRenderer` to PDF keeps SwiftUI shapes/text as vectors (text stays selectable), but `Image` assets and blend modes may rasterize; test a page early. Blend modes (`.multiply`) and large shadows can force rasterisation of the whole layer in PDF contexts; use sparingly and verify in the spike.

Real photo-textured assets from image 3 (pressed flowers, pins, ruled cards, torn dark-kraft scraps) are out of spec v1 except what spec lists; optionally add pin (thumbtack, code) and ruled-card lines (code) cheaply.

## 4. Proposed layout (inside the synchronized app folder, no pbxproj edits)

```
TravelJournal/
  DesignSystem/
    Tokens/        KraftColor.swift  KraftSpacing.swift  KraftMetrics.swift (margins 24/36, rotation range, tape/seal limits)
    Typography/    KraftFont.swift  FontRegistrar.swift  TextStyles.swift
    Theme/         Theme.swift (@Observable / EnvironmentKey: isPDF, margin, colorScheme lock, dynamic size cap)  SeededRandom.swift
    Shapes/        TornEdgeShape.swift  WashiShape.swift  StampPerforationShape.swift  WaxSealShape.swift  RouteDash.swift
    Components/    PolaroidView  TapedPhoto  NoteCard  HighlightStrip  PlaceTicket  PostmarkView  RatingStamp  (owned by D2/B1)
    Resources/
      Fonts/       *.ttf
      Textures/    (put images in Assets.xcassets instead)
    Gallery/       ComponentGalleryView.swift (#Preview)
  Assets.xcassets/
    Textures/paperGrain.imageset
    Icons/Category/cat_food ... cat_nature, cat_other   (.imageset PDF, template)
    Icons/Transport/tr_walk, tr_autorickshaw, tr_taxi, tr_bus, tr_train, tr_metro, tr_bike, tr_ferry
    Washi/washi_floral.imageset (only if raster)
Licenses/  (repo root, not in target)  Allura-OFL.txt  Lora-OFL.txt  Caveat-OFL.txt  SpecialElite-LICENSE.txt
```
Naming: types `Kraft*` (`KraftColor`, `KraftFont`, `KraftSpacing`), asset names `snake_case` with prefix `cat_` / `tr_` / `washi_`, enum-mapped (`Category.assetName`, `TransportMode.assetName`). Seeded rotation: `SeededRandom(seed: id.hashValue)` is NOT stable across launches (Swift hashing is randomised): use a stable hash (FNV-1a over `id.uuidString`) and a SplitMix64 generator; clamp rotation to -4...4 deg.

Metrics enum: `phoneMargin = 24`, `pdfMargin = 36`, `maxTapePerPhoto = 2`, `maxSealPerPage = 1`, `rotationRange = -4...4`, A4 = 595.2 x 841.8 pt.

## Open risks
1. PostScript names and static filenames are unverified (no download yet); a wrong name silently falls back to the system font. Verify after download via `fc-scan` and the debug assertion.
2. Special Elite licence is Apache 2.0 in google/fonts, not OFL as the spec claims; still free to bundle but ship the Apache notice. Verify at download time.
3. Lora/Caveat ship as variable fonts; static instances must be taken from the zip's `static/` folder (or generated), else weight/PS-name mismatch.
4. Procedural torn edges/postmark text-on-path may look synthetic versus image 3; time-box, with PNG-mask fallback decided at the Phase 0 prototype.
5. `ImageRenderer` PDF may rasterize blend modes/shadows/grain overlays and bloat file size; confirm in the spike (and cap shadow use).
6. Dynamic Type vs fixed story-page geometry: capped on story pages, so accessibility sizes are not honoured there (acceptable, document it); `lineSpacing` for the 24pt line height needs on-device tuning.
7. Spec lists 7 categories but 6 stamp icons (no `other` icon) and 8 transports incl. auto-rickshaw, which has no stock icon; needs custom art.
8. Forced light appearance is a product decision (no dark mode in v1) to confirm.
9. Icon sources (Noun Project etc.) have attribution terms; prefer MIT sets (Lucide/Phosphor/Tabler) or self-drawn.
10. Hash stability: use deterministic hashing for seeded rotation or app and PDF will diverge between launches.
