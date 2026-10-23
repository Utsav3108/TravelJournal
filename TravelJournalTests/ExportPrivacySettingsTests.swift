import XCTest
import SwiftData
@testable import TravelJournal

/// The settings UI's logic and persistence: global defaults survive a relaunch, a journey's override and a stop's
/// hide choice survive a save and refetch.
@MainActor
final class ExportPrivacySettingsTests: XCTestCase {
    private func suite() -> (UserDefaults, String) {
        let name = "export-privacy-settings-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return (UserDefaults(suiteName: name)!, name)
    }

    // MARK: Global defaults

    func testSettingsSaveEveryChangeAndSurviveRelaunch() {
        let (store, name) = suite()
        let settings = ExportPrivacySettings(defaults: ExportPrivacyDefaults(store: store))
        XCTAssertEqual(settings.privacy, ExportPrivacy())
        XCTAssertTrue(settings.isAtFactoryDefaults)

        settings.privacy.hideCosts = true
        settings.privacy.hideExactTimes = true
        settings.privacy.mapMode = .zoomedOut
        settings.privacy.hideStayStops = false
        XCTAssertFalse(settings.isAtFactoryDefaults)

        // A fresh suite object for the same domain stands in for the next launch.
        let relaunched = ExportPrivacySettings(defaults: ExportPrivacyDefaults(store: UserDefaults(suiteName: name)!))
        XCTAssertEqual(relaunched.privacy,
                       ExportPrivacy(hideStayStops: false, hideCosts: true, hideExactTimes: true, mapMode: .zoomedOut))
    }

    func testResetToDefaultsClearsTheSavedValue() {
        let (store, name) = suite()
        let settings = ExportPrivacySettings(defaults: ExportPrivacyDefaults(store: store))
        settings.privacy = ExportPrivacy(hideStayStops: false, hideCosts: true, mapMode: .hidden)
        XCTAssertNotNil(store.data(forKey: ExportPrivacyDefaults.key))

        settings.resetToDefaults()
        XCTAssertEqual(settings.privacy, ExportPrivacy())
        XCTAssertNil(store.data(forKey: ExportPrivacyDefaults.key), "reset leaves the key unset")
        XCTAssertEqual(ExportPrivacyDefaults(store: UserDefaults(suiteName: name)!).load(), ExportPrivacy())
    }

    func testReloadPicksUpChangesSavedElsewhere() {
        let (store, _) = suite()
        let defaults = ExportPrivacyDefaults(store: store)
        let settings = ExportPrivacySettings(defaults: defaults)
        defaults.save(ExportPrivacy(hideCosts: true))
        settings.reload()
        XCTAssertEqual(settings.privacy, ExportPrivacy(hideCosts: true))
    }

    // MARK: Journey override

    func testUseDefaultsToggleSeedsAndDropsTheOverride() {
        let (store, _) = suite()
        let defaults = ExportPrivacyDefaults(store: store)
        defaults.save(ExportPrivacy(hideCosts: true, mapMode: .zoomedOut))
        let j = JourneyFixtures.withStayStop().journey
        XCTAssertNil(j.exportPrivacy)

        JourneyPrivacyOverride.setUsesDefaults(false, journey: j, defaults: defaults)
        XCTAssertEqual(j.exportPrivacy, ExportPrivacy(hideCosts: true, mapMode: .zoomedOut), "seeded from the defaults")

        JourneyPrivacyOverride.set(ExportPrivacy(hideCosts: true, mapMode: .hidden), journey: j)
        // Choosing custom again keeps the override the journey already has.
        JourneyPrivacyOverride.setUsesDefaults(false, journey: j, defaults: defaults)
        XCTAssertEqual(j.exportPrivacy?.mapMode, .hidden)

        // Later changes to the defaults do not leak into a journey with its own settings.
        defaults.save(ExportPrivacy())
        XCTAssertEqual(ExportPrivacy.resolved(for: j, defaults: defaults).mapMode, .hidden)

        JourneyPrivacyOverride.setUsesDefaults(true, journey: j, defaults: defaults)
        XCTAssertNil(j.exportPrivacy)
        XCTAssertNil(j.exportPrivacyData)
        XCTAssertEqual(ExportPrivacy.resolved(for: j, defaults: defaults), ExportPrivacy())
    }

    func testUseDefaultsClearsUnreadableOverrideData() {
        let (store, _) = suite()
        let j = JourneyFixtures.oneStop().journey
        j.exportPrivacyData = Data("not json".utf8)
        JourneyPrivacyOverride.setUsesDefaults(true, journey: j, defaults: ExportPrivacyDefaults(store: store))
        XCTAssertNil(j.exportPrivacyData)
    }

    func testJourneyOverrideSurvivesSaveAndRefetch() throws {
        let f = JourneyFixtures.fourStops()
        let custom = ExportPrivacy(hideStayStops: false, hideCosts: true, hideExactTimes: true, mapMode: .hidden)
        JourneyPrivacyOverride.set(custom, journey: f.journey)
        try f.context.save()

        let fresh = ModelContext(f.container)
        let id = f.journey.id
        let refetched = try XCTUnwrap(fresh.fetch(FetchDescriptor<Journey>(predicate: #Predicate { $0.id == id })).first)
        XCTAssertEqual(refetched.exportPrivacy, custom)

        JourneyPrivacyOverride.setUsesDefaults(true, journey: refetched, defaults: ExportPrivacyDefaults(store: suite().0))
        try fresh.save()
        let again = try XCTUnwrap(ModelContext(f.container)
            .fetch(FetchDescriptor<Journey>(predicate: #Predicate { $0.id == id })).first)
        XCTAssertNil(again.exportPrivacy)
    }

    // MARK: Per-stop

    func testStopExportHiddenSurvivesSaveAndRefetch() throws {
        let f = JourneyFixtures.fourStops()
        f.stops[0].exportHidden = true
        f.stops[3].exportHidden = false
        try f.context.save()

        let fresh = ModelContext(f.container)
        let id = f.journey.id
        let j = try XCTUnwrap(fresh.fetch(FetchDescriptor<Journey>(predicate: #Predicate { $0.id == id })).first)
        XCTAssertEqual(j.orderedStops.map(\.exportHidden), [true, nil, nil, false])

        j.orderedStops[0].exportHidden = nil   // "Reset to automatic"
        try fresh.save()
        let again = try XCTUnwrap(ModelContext(f.container)
            .fetch(FetchDescriptor<Journey>(predicate: #Predicate { $0.id == id })).first)
        XCTAssertEqual(again.orderedStops.map(\.exportHidden), [nil, nil, nil, false])
    }

    func testStopVisibilityFollowsCategoryRuleUntilSetExplicitly() {
        let f = JourneyFixtures.withStayStop()
        let stay = f.stops[1], food = f.stops[2]
        let on = ExportPrivacy(), off = ExportPrivacy(hideStayStops: false)

        let stayAuto = StopExportVisibility(stop: stay, privacy: on)
        XCTAssertTrue(stayAuto.isHidden)
        XCTAssertFalse(stayAuto.isExplicit)
        XCTAssertTrue(stayAuto.footer.contains("Stay stops are hidden"), "Stay stops get the hint")

        XCTAssertFalse(StopExportVisibility(stop: stay, privacy: off).isHidden)
        XCTAssertFalse(StopExportVisibility(stop: stay, privacy: off).footer.contains("Stay stops are hidden"))

        let foodAuto = StopExportVisibility(stop: food, privacy: on)
        XCTAssertFalse(foodAuto.isHidden)
        XCTAssertTrue(foodAuto.footer.hasPrefix("Automatic"))

        stay.exportHidden = false
        let stayShown = StopExportVisibility(stop: stay, privacy: on)
        XCTAssertFalse(stayShown.isHidden, "the explicit choice wins over the Stay rule")
        XCTAssertTrue(stayShown.isExplicit)
        XCTAssertTrue(stayShown.footer.hasPrefix("Set for this stop"))

        food.exportHidden = true
        XCTAssertTrue(StopExportVisibility(stop: food, privacy: off).isHidden)
    }

    func testMapModeCopyCoversEveryMode() {
        for mode in ExportPrivacy.MapMode.allCases {
            XCTAssertFalse(ExportPrivacyCopy.name(mode).isEmpty)
            XCTAssertFalse(ExportPrivacyCopy.detail(mode).isEmpty)
        }
        XCTAssertEqual(Set(ExportPrivacy.MapMode.allCases.map(ExportPrivacyCopy.name)).count, 3)
    }
}
