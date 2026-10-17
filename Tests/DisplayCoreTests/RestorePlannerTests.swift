import XCTest
@testable import DisplayCore

final class RestorePlannerTests: XCTestCase {
    private func display(_ uuid: String, serial: UInt32 = 1, model: UInt32 = 10,
                         x: Int = 0, y: Int = 0, main: Bool = false, mirror: String? = nil) -> DisplayState {
        DisplayState(identity: DisplayIdentity(uuid: uuid, vendor: 100, model: model, serial: serial, isBuiltIn: false),
                     name: uuid, mode: DisplayMode(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080,
                                                  refreshRate: 60, ioFlags: 0),
                     x: x, y: y, rotation: 0, isMain: main, mirrorSourceUUID: mirror)
    }

    func testMissingMainReanchorsSurvivorsWithoutChangingRelativeArrangement() throws {
        let saved = [display("main", serial: 1, main: true),
                     display("left", serial: 2, x: -1920, y: 240),
                     display("upper", serial: 3, x: -1920, y: -840)]
        let live = [ConnectedDisplay(id: 20, state: display("left", serial: 2, main: true)),
                    ConnectedDisplay(id: 30, state: display("upper", serial: 3))]
        let result = try RestorePlanner.plan(saved: saved, connected: live)
        XCTAssertEqual(result.displays.map(\.displayID), [20, 30])
        XCTAssertEqual(result.displays.map(\.x), [0, 0])
        XCTAssertEqual(result.displays.map(\.y), [0, -1080])
        XCTAssertTrue(result.warnings.contains { $0.contains("main") && $0.contains("skipped") })
    }

    func testChangedUUIDUsesUniqueHardwareSerial() throws {
        let result = try RestorePlanner.plan(saved: [display("old", serial: 99, main: true)],
                                             connected: [ConnectedDisplay(id: 7, state: display("new", serial: 99, main: true))])
        XCTAssertEqual(result.displays.map(\.displayID), [7])
        XCTAssertTrue(result.warnings.contains { $0.contains("ID changed") })
    }

    func testReusedUUIDCannotOverrideConflictingHardwareSerial() throws {
        let saved = [display("old", serial: 99, main: true)]
        let live = [ConnectedDisplay(id: 1, state: display("old", serial: 22)),
                    ConnectedDisplay(id: 2, state: display("new", serial: 99, main: true))]
        let result = try RestorePlanner.plan(saved: saved, connected: live)
        XCTAssertEqual(result.displays.first?.displayID, 2)
        XCTAssertEqual(result.displays.first?.x, 0)
    }

    func testIdenticalUnserializedMonitorsAreNotGuessed() {
        let saved = [display("old-a", serial: 0, main: true), display("old-b", serial: 0, x: 1920)]
        let live = [ConnectedDisplay(id: 1, state: display("new-a", serial: 0, main: true)),
                    ConnectedDisplay(id: 2, state: display("new-b", serial: 0))]
        XCTAssertThrowsError(try RestorePlanner.plan(saved: saved, connected: live)) { error in
            guard case RestorePlanningError.noMatchingDisplays = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testOneRemainingIdenticalMonitorDoesNotConsumeMissingMonitorsSettings() throws {
        let saved = [display("known", serial: 0, main: true), display("missing", serial: 0, x: 1920)]
        let live = [ConnectedDisplay(id: 1, state: display("known", serial: 0, main: true))]
        let result = try RestorePlanner.plan(saved: saved, connected: live)
        XCTAssertEqual(result.displays.count, 1)
        XCTAssertEqual(result.displays[0].saved.id, "known")
        XCTAssertTrue(result.warnings.contains { $0.contains("missing") && $0.contains("skipped") })
    }

    func testMissingMirrorSourcePromotesFollowerAndKeepsOtherFollowersMirrored() throws {
        let saved = [display("source", serial: 1, main: true),
                     display("follower", serial: 2, mirror: "source"),
                     display("other", serial: 3, mirror: "source")]
        let live = [ConnectedDisplay(id: 2, state: display("follower", serial: 2, main: true)),
                    ConnectedDisplay(id: 3, state: display("other", serial: 3))]
        let result = try RestorePlanner.plan(saved: saved, connected: live)
        XCTAssertNil(result.displays[0].mirrorSourceID)
        XCTAssertEqual(result.displays[1].mirrorSourceID, 2)
        XCTAssertEqual(result.displays[0].x, 0)
        XCTAssertEqual(result.displays[0].y, 0)
    }

    func testUnsavedConnectedDisplayRemainsUsableToTheRight() throws {
        let saved = [display("saved", serial: 1, main: true)]
        let extra = display("extra", serial: 2, main: true)
        let result = try RestorePlanner.plan(saved: saved, connected: [
            ConnectedDisplay(id: 1, state: display("saved", serial: 1)), ConnectedDisplay(id: 2, state: extra)
        ])
        XCTAssertEqual(result.displays.map(\.displayID), [1, 2])
        XCTAssertEqual(result.displays[0].x, 0)
        XCTAssertEqual(result.displays[1].x, 1920)
        XCTAssertEqual(result.displays[1].saved.mode, extra.mode)
        XCTAssertNil(result.displays[1].mirrorSourceID)
    }

    func testMirrorCyclesAreRejectedBeforeAnyHardwareWork() {
        let saved = [display("a", serial: 1, mirror: "b"), display("b", serial: 2, mirror: "a")]
        XCTAssertThrowsError(try RestorePlanner.plan(saved: saved, connected: [
            ConnectedDisplay(id: 1, state: saved[0]), ConnectedDisplay(id: 2, state: saved[1])
        ]))
    }

    func testModeMatchingPreservesScalingAndRefreshRate() {
        let base = DisplayMode(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60, ioFlags: 0)
        var candidate = base
        candidate.refreshRate = 59.94
        XCTAssertTrue(base.matches(candidate))
        candidate.refreshRate = 75
        XCTAssertFalse(base.matches(candidate))
        candidate = base
        candidate.pixelWidth = 1920
        candidate.pixelHeight = 1080
        XCTAssertFalse(base.matches(candidate))
        candidate = base
        candidate.refreshRate = 0
        XCTAssertFalse(base.matches(candidate))
        candidate = base
        candidate.ioFlags = 0x40
        XCTAssertFalse(base.matches(candidate))
    }
}
