# L2 - Photo to Place pipeline (research)

Target: iOS 27.0 (`IPHONEOS_DEPLOYMENT_TARGET = 27.0` in project.pbxproj), Swift 5 mode, `GENERATE_INFOPLIST_FILE = YES`. So no availability shims are needed; every iOS 16-26 API below is usable directly.
Verified against Apple docs/forums (WebSearch, Oct 2026): `MKReverseGeocodingRequest` and `MKGeocodingRequest` (iOS 26.0+) are the replacements for `CLGeocoder`. Items marked VERIFY-IN-XCODE are signatures from memory that must be confirmed against the SDK at build time.

## 1. Photo picking

### 1.1 Library: PhotosPicker
```swift
import PhotosUI
@State private var picks: [PhotosPickerItem] = []

PhotosPicker(selection: $picks,
             maxSelectionCount: 40,
             selectionBehavior: .ordered,
             matching: .images,
             photoLibrary: .shared()) {      // REQUIRED to get itemIdentifier
    Label("Add photos", systemImage: "photo.on.rectangle")
}
```
- `PhotosPickerItem.itemIdentifier` is `nil` unless `photoLibrary: .shared()` is passed. With it, it is the `PHAsset.localIdentifier`.
- The picker runs out of process: **no permission prompt is needed to pick**. Permission is only needed to turn the identifier into a `PHAsset` (for GPS/date). That is the key product decision (see 1.3).
- Resolve metadata:
```swift
struct PhotoMeta { var id: String?; var coord: CLLocationCoordinate2D?; var date: Date?; var source: Source
  enum Source { case asset, exif, none } }

func meta(for item: PhotosPickerItem) async -> PhotoMeta {
    if let id = item.itemIdentifier,
       let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
        return .init(id: id, coord: asset.location?.coordinate, date: asset.creationDate, source: .asset)
    }
    // Fallback: EXIF from the file data
    if let data = try? await item.loadTransferable(type: Data.self) { return exifMeta(data) }
    return .init(id: nil, coord: nil, date: nil, source: .none)
}
```
- `PHAsset.location` (CLLocation?) and `creationDate` are the best source: they include user-edited location/date from Photos.
- **Limited access caveat:** if status is `.limited`, `fetchAssets(withLocalIdentifiers:)` only returns assets in the limited set; picks outside it come back empty. So always fall through to EXIF when the fetch is empty. Do not nag the user to "allow all"; EXIF fallback makes limited access fine.
- Request level: `PHPhotoLibrary.requestAuthorization(for: .readWrite)` (the `.addOnly` level cannot read). Read `PHPhotoLibrary.authorizationStatus(for: .readWrite)` first; only prompt when `.notDetermined`. If `.denied`/`.restricted`, skip the asset path silently and use EXIF (the picker still works).
- Persist `localIdentifier` on `Photo` only as a hint; the app must copy the image data into its own store (L1) because the library asset can be deleted. Never rely on the identifier for display.

### 1.2 EXIF fallback (no asset id, or fetch empty)
```swift
import ImageIO
func exifMeta(_ data: Data) -> PhotoMeta {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return .init(...none) }
    var coord: CLLocationCoordinate2D?
    if let gps = p[kCGImagePropertyGPSDictionary] as? [CFString: Any],
       var lat = gps[kCGImagePropertyGPSLatitude] as? Double,
       var lon = gps[kCGImagePropertyGPSLongitude] as? Double {
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
        coord = .init(latitude: lat, longitude: lon)
    }
    var date: Date?
    if let ex = p[kCGImagePropertyExifDictionary] as? [CFString: Any],
       let s = ex[kCGImagePropertyExifDateTimeOriginal] as? String {
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX"); f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        // EXIF has no timezone unless OffsetTimeOriginal ("+05:30") is present; default to TimeZone.current
        date = f.date(from: s)
    }
    return .init(id: nil, coord: coord, date: date, source: .exif)
}
```
- Lat/Lon are unsigned magnitudes; the Ref keys carry the sign (common bug).
- `CGImageSourceCreateWithData` with `kCGImageSourceShouldCache: false` avoids decoding. Only read the properties.
- Caveat: when the user taps "Options" in the system picker and turns Location off, the returned data has GPS stripped. We cannot distinguish that from "never had GPS"; treat both as "no GPS".
- Caveat: the loaded `Data` for HEIC may be transcoded to JPEG; EXIF still carries over. Large selections: load sequentially (or 3 at a time), downsample with `CGImageSourceCreateThumbnailAtIndex` and write to disk immediately to avoid memory spikes.
- Cheap path: when the asset exists, do not load Data for metadata at all; load only when copying into the store.

### 1.3 Camera capture
No SwiftUI-native camera view; wrap `UIImagePickerController` (still supported, not deprecated as of iOS 26):
```swift
struct CameraView: UIViewControllerRepresentable {
    var onImage: (UIImage, Date) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController(); c.sourceType = .camera; c.delegate = context.coordinator; return c }
    // Coordinator: imagePickerController(_:didFinishPickingMediaWithInfo:) -> info[.originalImage] as? UIImage
}
// guard UIImagePickerController.isSourceTypeAvailable(.camera)   // false on Simulator
```
- Present with `.fullScreenCover`. Needs `NSCameraUsageDescription`; the system prompts at first use, so no pre-ask code needed. Handle `.denied` with an "Open Settings" alert (`UIApplication.openSettingsURLString`).
- **Metadata:** the `UIImage` from `.originalImage` has no EXIF and no GPS. The camera does not tag location in that path. Strategy: timestamp = `Date()` at capture (accurate); coordinate = last known `CLLocation` only if location permission is already granted (one-shot `CLLocationManager.requestLocation()`), else none, and the stop lands in "Find this place". Do NOT prompt for location just for camera shots; the spec says location only on map search. Optionally offer to reuse the location authorization if already granted.
- Saving camera photos to Photos library is out of scope (would need `NSPhotoLibraryAddUsageDescription`); save only into the app store.
- Alternative with richer metadata: `PHPickerViewController`/AVFoundation `AVCapturePhotoOutput` (embeds EXIF, GPS if you pass location); not worth it for v1.

## 2. Info.plist keys and permission timing
The project has `GENERATE_INFOPLIST_FILE = YES` and no Info.plist file, so add keys as build settings (Target > Build Settings > search "Info.plist Values", or Info tab), in both Debug and Release config of the app target (`INFOPLIST_KEY_*` entries in project.pbxproj, next to `INFOPLIST_KEY_UILaunchScreen_Generation`):

| Key (build setting) | Purpose | Copy |
|---|---|---|
| `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` | read GPS/time of picked photos (PHAsset) | "TravelJournal reads the place and time of the photos you pick, to group them into stops. Photos stay on your device." |
| `INFOPLIST_KEY_NSCameraUsageDescription` | camera sheet | "Take photos to add to your story." |
| `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` | map search centred on you; camera shot tag | "Used to centre place search near you. Never tracked in the background." |
- Missing key = hard crash on request, so add all three before writing the code. Not needed: `NSPhotoLibraryAddUsageDescription`, Always-location, `NSMotion*`.
- Any custom (non `INFOPLIST_KEY_`-supported) key needs a real Info.plist; these three are all supported as `INFOPLIST_KEY_` names (VERIFY-IN-XCODE that they show in the Info tab after build).
- **When to ask (spec: in context, not onboarding):**
  1. Step 3 "Add photos": show an explainer card ("We'll read the place and time from your photos") with button "Choose photos". Opening PhotosPicker needs no permission. Immediately after the user confirms the selection, if status is `.notDetermined` call `requestAuthorization(for: .readWrite)`. Deny/limited does not block; it just means EXIF fallback.
  2. Location: only when the user opens place search (step 4 map search) and taps "Near me". Call `CLLocationManager.requestWhenInUseAuthorization()`; if denied, search by city name/region only.
  3. Camera: system prompt at first present of CameraView.
- Wrap each in a small `PermissionState` enum (`notDetermined/granted/limited/denied`) in a single `PermissionService` so UI shows consistent denied copy.

## 3. Clustering photos into suggested stops

### 3.1 Config
```swift
struct ClusterConfig {
    var maxDistance: CLLocationDistance = 150     // m, photo to cluster centroid
    var maxGap: TimeInterval = 30 * 60            // s, between consecutive photos
    var maxSpan: TimeInterval = 3 * 3600          // s, safety cap for one stop
    var mergeDistance: CLLocationDistance = 100   // m, post-pass merging adjacent clusters
    var noTimeAttachRadius: CLLocationDistance = 150
    var maxPhotosPerStop = 4                      // spec: 0-4; extras become "unassigned" overflow, user trims
}
```
Everything tunable in this one struct, injected into `PhotoClusterer`. Pure function, no UIKit/Photos imports, so it is fully unit-testable.

### 3.2 Algorithm (sequential greedy, time-ordered)
Input `[PhotoMeta]` with `coord?`, `date?`. Output `[Cluster]` (+ `unplaced`).
1. Partition: `timed = photos with date`, `untimed`. Sort `timed` by date (stable, tie-break by identifier).
2. Walk `timed` in order, maintaining `current` cluster (running centroid of GPS photos, `first/last` dates).
   Start a **new cluster** if any holds:
   - `photo.date - current.last > maxGap`
   - both have GPS and `distance(photo, current.centroid) > maxDistance`
   - `photo.date - current.first > maxSpan`
   Otherwise append and update centroid (mean of lat/lon is fine at city scale).
   - Photo **without GPS** but with time: joins `current` if the time-gap test passes (it was taken right after a photo at that place); flag `inferredLocation = true`. If `current` has no GPS at all, still joins; cluster has `coord = nil` until a GPS member arrives.
3. Post-pass: merge adjacent clusters if `distance(centroids) <= mergeDistance` and the gap `<= 2*maxGap` (user wandered inside a market). Do not merge non-adjacent ones: revisiting the hotel later is a legitimately separate stop (a journey has ordered stops, repeated places are fine).
4. Photos **with GPS but no time** (rare; edited/screenshots): attach to the nearest cluster centroid within `noTimeAttachRadius`; otherwise create their own cluster (ordered after timed ones by nearest-neighbour, or at the end).
5. Photos with **neither**: put in `unplaced`; shown as a tray "N photos without place or time. Drag onto a stop". Never silently dropped. Default hint: if the picker returned them in a contiguous run after a cluster (`.ordered` selection), suggest that cluster.
6. Cluster fields: `photos`, `coord` (centroid of GPS members, or `nil`), `arrival = first date`, `span = last - first`, `hero = first photo with GPS closest to centroid` (v1.1 allows user pick; v1 default first).
7. Cap: if a cluster has more than `maxPhotosPerStop`, keep all in cluster but mark the top 4 (closest to centroid, earliest tie-break) as selected; UI asks the user to confirm the 4.
Complexity O(n log n). DBSCAN is not used: it is not order-aware, and chaining in a dense city could daisy-chain a walk into one blob; the sequential variant also gives stop order for free.

Why drift-free: comparing against the running centroid (not just the previous photo) prevents a slow walk from chaining indefinitely; `maxSpan` is a backstop.

### 3.3 Test plan (XCTest, no device)
Fixtures as `[PhotoMeta]` literals, 19 Oct 2026, IST (UTC+5:30). Mumbai coordinates (approximate):
- CST: 18.9398, 72.8355 | Sardar Pav Bhaji (Tardeo): 18.9712, 72.8113 | Siddhivinayak: 19.0169, 72.8301 | hotel: 19.0176, 72.8562 (any hotel point >150 m from Siddhivinayak).

| Test | Fixture | Expect |
|---|---|---|
| happy path | 3 photos at CST 09:00-09:10, 4 at pav bhaji 11:30-12:00, 3 at temple 14:00-14:20, 2 at hotel 17:00 | 4 clusters, order by time, arrival = first photo, span as computed |
| time gap splits | same coord, photos 09:00, 09:10, 10:00 | 2 clusters (gap 50 min) |
| distance splits | two coords 400 m apart, 2 min apart | 2 clusters |
| within threshold | coords 120 m apart, 5 min | 1 cluster |
| boundary | 150 m exactly / 30:00 exactly | defined behaviour (`>` splits; test documents it) |
| no GPS, has time | 1 photo no GPS at 09:05 between two CST photos | joins CST, `inferredLocation` true |
| no GPS first | no-GPS photo at 08:59 then GPS photos 09:00 | joins following cluster only if gap ok; test the rule chosen |
| all no GPS | 5 photos with times, no coords | clustered by time only, `coord == nil` |
| GPS, no time | photo at pav bhaji coord, no date | attaches to pav bhaji cluster |
| neither | 2 bare photos | `unplaced` of 2 |
| unsorted input | shuffled fixture | same output as sorted |
| revisit | hotel 09:00, CST 10:00, hotel 18:00 | 3 clusters, not merged |
| max span | 1 photo / 20 min over 4 h at one point | split at `maxSpan` |
| config | `maxDistance = 500` | merges the 400 m case |
| time zone | EXIF-parsed dates in non-device zone | stays monotonic (use `Date`, never strings) |
| perf | 500 synthetic photos | < 50 ms |
Threshold spike (ask Phase 0 owner): run clusterer on 2-3 real personal day-trip albums on device, log cluster counts for maxDistance in {100,150,250} m and maxGap in {20,30,45} min; keep defaults unless over/under-splitting is obvious.

## 4. Place name from GPS

### 4.1 Lookup chain per cluster (only when `coord != nil`)
1. **POI near coordinate:**
```swift
let req = MKLocalPointsOfInterestRequest(center: coord, radius: 75)  // m
req.pointOfInterestFilter = .includingAll
let items = try await MKLocalSearch(request: req).start().mapItems
```
   Rank by distance to `coord` (CLLocation distance of `item.placemark.coordinate`), take the nearest within ~75 m as suggestion #1, list the next 3-4 as alternates in a "Not right? Pick another" sheet. Auto-pick only if exactly one is within 40 m or nearest is < 50% of the 2nd's distance; otherwise show the list with the nearest preselected. `item.name` -> place name; `item.pointOfInterestCategory` -> default Category (map: `.restaurant/.cafe/.bakery` -> food; `.museum/.nationalMonument` -> landmark; `.hotel` -> stay; `.store` -> shopping; `.park/.beach/.nationalPark` -> nature; place of worship is not a dedicated POI category: infer "temple" from name/Hindi keywords `mandir|temple|masjid|church`, else landmark). Verify category constants in SDK.
2. **Reverse geocode (area/street name, no POI hit):** prefer the iOS 26+ API since `CLGeocoder` is deprecated:
```swift
if let r = MKReverseGeocodingRequest(location: CLLocation(latitude: c.latitude, longitude: c.longitude)) {
    let items = try await r.mapItems          // VERIFY-IN-XCODE: async accessor name (docs: getMapItems / mapItems)
    // items.first?.name, .address (MKAddress), .addressRepresentations (city/region/fullAddress)
}
```
   Forum-confirmed gotchas: results are `MKMapItem` with **no `CNPostalAddress`**; use `MKAddressRepresentations` (e.g. city name, full address string) for display. There is no replacement for `CLPlacemark.region`. Use the name as "Near <street/neighbourhood>" with status `areaOnly`. `CLGeocoder.reverseGeocodeLocation` still works but is deprecated: do not use it.
3. **Nothing / offline / error:** stop state `needsPlace` -> "Find this place" card (opens search sheet, Section 4.3). Coordinate is still stored so the pin appears on the map; the name is mandatory (spec), so the user must type/search before the stop is complete. Provide "Use coordinates as name" never; offer a plain text field.

### 4.2 Auto-fill of defaults
- User can always edit; the pipeline only proposes (`PlaceSuggestion { name, category?, address?, coord, confidence }`).
- Location saved = **the photo cluster centroid** vs **the POI coordinate**: use POI coordinate + address when a POI was accepted; centroid otherwise.

### 4.3 Search fallback
```swift
let r = MKLocalSearch.Request()
r.naturalLanguageQuery = text
r.region = MKCoordinateRegion(center: anchor, latitudinalMeters: 15_000, longitudinalMeters: 15_000)
r.resultTypes = [.pointOfInterest, .address]
let res = try await MKLocalSearch(request: r).start()
```
- `anchor` priority: cluster coord -> previous/next stop coord -> journey city geocode centre -> user location (only if already granted) -> none (global search).
- Use `MKLocalSearchCompleter` (`queryFragment`, `region`, `resultTypes`) for type-ahead; on selection do an `MKLocalSearch(request: .init(completion:))`. Debounce 300 ms.
- Search is a sheet over a map; asking location permission only from a "Near me" button here (Section 2).

### 4.4 Offline, throttling, caching
- Offline is the expected case in transit: `MKError.networkUnavailable`/`URLError`/timeouts -> stop `pendingLookup`; persist and **retry automatically when `NWPathMonitor` reports satisfied**, or via a "Try again" button. Everything except place lookup works offline (spec).
- Apple's limits: `CLGeocoder` documents rate limiting (error `.network`, throttled; roughly 50 requests/60 s per app, documented loosely); MKLocalSearch/MKReverseGeocodingRequest docs do not state a limit (open forum question). Treat both as limited: run lookups **serially via an actor queue** with ~1 req/s spacing and a max ~10 clusters per import; cancel on view dismissal; on a throttle error back off exponentially (2s, 4s, 8s) and surface "Find this place".
- Cache in SwiftData/UserDefaults keyed by coordinate rounded to ~3 decimals (≈110 m) -> `PlaceSuggestion`; also cache negative results briefly (10 min). Dedupe: clusters within 100 m reuse one result. Never lookup per photo, only per cluster, and once per cluster centroid (retry only on edit/refresh).
- Lookups occur after clustering, in the background with a per-card spinner; the grouped result renders immediately.

## 5. Derived defaults
| Field | Default | Rule |
|---|---|---|
| Stop arrival time | first photo date in cluster (`PHAsset.creationDate` / EXIF), nil if no times | editable |
| Time spent | `last - first` photo date, rounded up to 5 min; **nil if span < 5 min or only 1 photo** (do not display "spent 0 min"). Hint chip "estimate from photos" | for the final stop span understates stay; fine, editable |
| Journey date | date of the earliest photo in the whole import (device-local calendar day) | spec |
| City | first stop with a location: `addressRepresentations.cityName` from the reverse geocode (or `placemark.locality`) | fill only if journey.city empty; do not overwrite user text; if offline, leave empty and fill on retry |
| Cover photo | first stop's hero photo | spec |
| Category | from POI category (4.1) | else nil |
| Leg km/min suggestion | v1: leave empty, or haversine distance between stop coords x 1.3 as a pre-fill hint (v1.1 uses MKDirections); minutes = arrival difference minus the previous stop's time spent (if both exist) | label "estimated" |
- Stop order = cluster order by time. If the user drags to reorder, keep the stored arrival times as-is (they are facts, not order).
- A stop with no GPS stays off the map, as in the spec.

## 6. Risk: photos without GPS (WhatsApp, screenshots, downloads, "Location off" shares)
Facts: WhatsApp, Instagram, Telegram etc. strip EXIF GPS; they often keep (file) date = *received* date, not the shot date. `PHAsset.creationDate` for these is the save time; so even time grouping is unreliable.
UX flow (consistent with spec step 4 "Find this place"):
1. After import show suggestions list: green "Located" cards and an amber section "Needs a place (N)". No error tone.
2. Amber card: thumbnails, text "No location in these photos. They may have been shared via a messaging app." with primary button **Find this place** (opens search sheet, Section 4.3, anchored to neighbouring stops/journey city) and secondary "Move to another stop".
3. Time-only photos are auto-joined to the preceding time-adjacent cluster as a *suggestion* with an "inferred" chip; user taps to confirm or detach. Photos with a "suspicious" time (creation date more than 24 h away from the median of GPS photos, or exact same minute as import) are not auto-joined; they go to the tray.
4. Selecting a search result sets place name, category, coordinate (stop now appears on the map); multi-select "Apply to all N photos".
5. If a whole import has no GPS at all: skip clustering by distance, group by time only, and open "Find this place" for each; banner "Tip: choose photos straight from your library (not via WhatsApp) to detect places automatically".
6. Hint text in the picker explainer: "Photos you saved from chat apps usually have no location."
Test: fixtures in 3.3 (no GPS rows) + manual run with a WhatsApp-forwarded image.

## Open risks
1. **Limited library / Options toggle:** `.limited` access or "Location off" in the picker silently produces no GPS; indistinguishable from true no-GPS. Mitigation is only UX (Section 6). Needs a device test across iOS 27 behaviours (PhotosPicker + `itemIdentifier` + limited, is the fetch result empty or not?).
2. **Reverse geocoding API surface is new and thin:** `MKReverseGeocodingRequest` exact async signature, `MKAddressRepresentations` property names, and city-name availability need compile verification; no structured `CNPostalAddress`, no `region`. Rate limits for the MapKit replacement are undocumented, so we throttle defensively.
3. **POI accuracy in dense Mumbai:** stalls/temples within 50 m of each other; wrong auto-pick is likely. Mitigation: always show alternates, never silently finalize; place-of-worship category inferred by name only.
4. **Camera photos:** no GPS without location permission, which spec defers; camera-first users will see more "Find this place". Decide whether to request location at first camera use (deviation from spec) or accept.
5. **Time reliability:** EXIF has no timezone (travel across zones, UTC vs local); WhatsApp dates are receive dates; clusters can be wrong for those. Threshold values (150 m / 30 min) are untested on real data; spike required.
6. **Memory/perf on 40-photo imports** (HEIC decode, sequential load) and the limit of 4 photos per stop vs larger clusters (UX for choosing which 4).
7. **Deprecation watch:** `CLGeocoder` reverse/forward is deprecated (iOS 26); `CLPlacemark.region` deprecated with no MapKit replacement; do not depend on either. `UIImagePickerController` still supported but legacy; `PHPickerViewController` options unaffected.
8. `INFOPLIST_KEY_` entries must be edited in project settings (both configs); forgetting one crashes on first use of that permission.

Sources: [MKReverseGeocodingRequest forum thread](https://developer.apple.com/forums/thread/795687), [CLPlacemark.region replacement thread](https://developer.apple.com/forums/thread/794546), [MKReverseGeocodingRequest docs](https://developer.apple.com/documentation/mapkit/mkreversegeocodingrequest).
