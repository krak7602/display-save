import XCTest
@testable import DisplayCore

final class PresetStoreTests: XCTestCase {
    private func preset(_ name: String = "Desk") -> DisplayPreset {
        DisplayPreset(name: name, createdAt: Date(timeIntervalSince1970: 1_700_000_000), displays: [
            DisplayState(identity: DisplayIdentity(uuid: "screen", vendor: 1, model: 2, serial: 3, isBuiltIn: true),
                         name: "Built-in Display", mode: DisplayMode(width: 1512, height: 982, pixelWidth: 3024,
                                                                    pixelHeight: 1964, refreshRate: 0, ioFlags: 0),
                         x: 0, y: 0, rotation: 0, isMain: true, mirrorSourceUUID: nil)
        ])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testSavedLayoutsSurviveReopeningAndDeletion() throws {
        let directory = try temporaryDirectory()
        let store = try PresetStore(directory: directory)
        let desk = preset()
        let travel = preset("Travel")
        try store.save([desk, travel])
        XCTAssertEqual(try PresetStore(directory: directory).load(), [desk, travel])
        try store.save([travel])
        XCTAssertEqual(try PresetStore(directory: directory).load(), [travel])
    }

    func testCorruptStoreCannotBeOverwrittenBySave() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("presets.json")
        let damaged = Data("{incomplete".utf8)
        try damaged.write(to: file)
        let store = try PresetStore(directory: directory)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save([preset()]))
        XCTAssertEqual(try Data(contentsOf: file), damaged)
    }

    func testFutureVersionIsPreserved() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("presets.json")
        let future = Data("{\"version\":99,\"presets\":[]}".utf8)
        try future.write(to: file)
        let store = try PresetStore(directory: directory)
        XCTAssertThrowsError(try store.load()) { error in
            guard case PresetStoreError.unsupportedVersion(99) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertThrowsError(try store.save([]))
        XCTAssertEqual(try Data(contentsOf: file), future)
    }

    func testDuplicateNamesCannotErasePreviouslySavedLayout() throws {
        let directory = try temporaryDirectory()
        let store = try PresetStore(directory: directory)
        let original = preset()
        try store.save([original])
        XCTAssertThrowsError(try store.save([original, preset("desk")]))
        XCTAssertEqual(try store.load(), [original])
    }
}
