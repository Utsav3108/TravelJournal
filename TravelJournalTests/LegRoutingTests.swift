import XCTest
@testable import TravelJournal

private final class FakeBackend: LegDirectionsBackend, @unchecked Sendable {
    var result: Result<[Coordinate], Error>
    private(set) var calls = 0
    init(_ result: Result<[Coordinate], Error>) { self.result = result }
    func route(from: Coordinate, to: Coordinate, transport: MapsTransport) async throws -> [Coordinate] {
        calls += 1
        return try result.get()
    }
}

private struct Boom: Error {}

@MainActor
final class LegRoutingTests: XCTestCase {
    private func stop(_ id: String, _ lat: Double?, _ lon: Double?) -> OverviewStop {
        OverviewStop(id: id, number: 1, name: id, latitude: lat, longitude: lon)
    }
    private func leg(_ mode: TransportMode?) -> StoryLeg {
        StoryLeg(id: UUID().uuidString, modeRaw: mode?.rawValue, km: nil, minutes: nil, story: nil)
    }
    private func model(_ stops: [OverviewStop], _ legs: [StoryLeg]) -> OverviewModel {
        OverviewModel(stops: stops, legs: legs,
                      stats: StatsModel(stops: stops.count, km: nil, totalMinutes: 0, travelMinutes: 0,
                                        modes: [], photos: 0, moneyText: nil))
    }
    private func seg(_ mode: TransportMode) -> LegSegment {
        LegSegment(id: "a->b", fromStopID: "a", toStopID: "b", from: Coordinate(latitude: 1, longitude: 2),
                   to: Coordinate(latitude: 3, longitude: 4), mode: mode)
    }

    func testEveryModeHasExpectedStrategy() {
        for mode in TransportMode.allCases {
            let expected: RouteStrategy
            switch mode {
            case .walk: expected = .directions(.walking)
            case .taxi, .autoRickshaw: expected = .directions(.driving)
            case .bike: expected = .directions(.cycling)
            case .bus, .localTrain, .metro: expected = .directions(.transit)
            case .ferry: expected = .straightLine
            }
            XCTAssertEqual(LegRouting.strategy(for: mode), expected, "\(mode)")
        }
    }

    func testStylesAreDistinct() {
        XCTAssertNotEqual(LegRouting.style(for: .taxi), LegRouting.style(for: .metro))
        XCTAssertNotEqual(LegRouting.style(for: .taxi), LegRouting.style(for: .walk))
        XCTAssertNotEqual(LegRouting.style(for: .metro), LegRouting.style(for: .walk))
        XCTAssertNotEqual(LegRouting.style(for: .walk), LegRouting.style(for: .ferry))
        XCTAssertNotEqual(LegRouting.style(for: .bus), LegRouting.style(for: .taxi))
        XCTAssertTrue(LegRouting.style(for: .taxi).dash.isEmpty)
        XCTAssertFalse(LegRouting.style(for: .walk).dash.isEmpty)
    }

    func testSegmentsJoinLocatedNeighboursSkippingOthers() {
        let m = model([stop("a", 1, 1), stop("b", nil, nil), stop("c", 3, 3), stop("d", 4, 4)],
                      [leg(.taxi), leg(.bus), leg(.metro)])
        let s = LegRouting.segments(for: m)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].fromStopID, "a"); XCTAssertEqual(s[0].toStopID, "c")
        XCTAssertEqual(s[0].mode, .taxi)
        XCTAssertEqual(s[1].fromStopID, "c"); XCTAssertEqual(s[1].mode, .metro)
        XCTAssertEqual(s[1].to, Coordinate(latitude: 4, longitude: 4))
    }

    func testFewerThanTwoLocatedGivesNoSegments() {
        XCTAssertTrue(LegRouting.segments(for: model([stop("a", 1, 1), stop("b", nil, 2)], [leg(.walk)])).isEmpty)
        XCTAssertTrue(LegRouting.segments(for: model([], [])).isEmpty)
    }

    func testMissingModeDefaultsToWalk() {
        let s = LegRouting.segments(for: model([stop("a", 1, 1), stop("b", 2, 2)], [leg(nil)]))
        XCTAssertEqual(s.first?.mode, .walk)
    }

    func testSuccessReturnsPolyline() async {
        let line = [Coordinate(latitude: 1, longitude: 2), Coordinate(latitude: 2, longitude: 3), Coordinate(latitude: 3, longitude: 4)]
        let svc = LegRouteService(backend: FakeBackend(.success(line)))
        let result = await svc.route(for: seg(.taxi))
        XCTAssertEqual(result, line)
    }

    func testErrorAndEmptyFallBackToStraightLine() async {
        let s = seg(.walk)
        let straight = [s.from, s.to]
        let r1 = await LegRouteService(backend: FakeBackend(.failure(Boom()))).route(for: s)
        let r2 = await LegRouteService(backend: FakeBackend(.success([]))).route(for: s)
        XCTAssertEqual(r1, straight)
        XCTAssertEqual(r2, straight)
    }

    func testCacheAvoidsSecondBackendCall() async {
        let backend = FakeBackend(.success([Coordinate(latitude: 1, longitude: 2), Coordinate(latitude: 3, longitude: 4)]))
        let svc = LegRouteService(backend: backend)
        _ = await svc.route(for: seg(.taxi))
        _ = await svc.route(for: seg(.taxi))
        XCTAssertEqual(backend.calls, 1)
    }

    func testStraightLineModeNeverCallsBackend() async {
        let backend = FakeBackend(.success([]))
        let s = seg(.ferry)
        let result = await LegRouteService(backend: backend).route(for: s)
        XCTAssertEqual(result, [s.from, s.to])
        XCTAssertEqual(backend.calls, 0)
    }

    func testRoutesStreamYieldsEverySegment() async {
        let svc = LegRouteService(backend: FakeBackend(.failure(Boom())))
        var a = seg(.walk); a.id = "1"; a.to = Coordinate(latitude: 9, longitude: 9)
        var b = seg(.taxi); b.id = "2"
        var got = Set<String>()
        for await (s, _) in svc.routes(for: [a, b, seg(.ferry)]) { got.insert(s.id) }
        XCTAssertEqual(got, ["1", "2", "a->b"])
    }
}
