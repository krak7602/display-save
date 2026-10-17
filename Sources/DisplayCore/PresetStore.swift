import Foundation

public enum PresetStoreError: LocalizedError {
    case unsupportedVersion(Int)
    case unreadable(String)
    case invalidPresets

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "These layouts were saved by a newer Display Save (format \(version)). Update the app before changing them."
        case .unreadable(let path):
            return "Saved layouts could not be read at \(path). The file has not been overwritten. Restore a valid copy and reopen Display Save."
        case .invalidPresets:
            return "Layouts must have unique names and IDs, and contain valid display snapshots. No changes were saved."
        }
    }
}

public struct PresetStore {
    private struct Envelope: Codable {
        var version: Int
        var presets: [DisplayPreset]
    }
    private struct Version: Decodable { var version: Int }
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("presets.json") }

    public init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory
        } else {
            self.directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false
            ).appendingPathComponent("Display Save", isDirectory: true)
        }
    }

    public func load() throws -> [DisplayPreset] {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        } catch {
            throw PresetStoreError.unreadable(file.path)
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let version = try decoder.decode(Version.self, from: data).version
            guard version == 1 else { throw PresetStoreError.unsupportedVersion(version) }
            let presets = try decoder.decode(Envelope.self, from: data).presets
            try validate(presets)
            return presets
        } catch let error as PresetStoreError {
            throw error
        } catch {
            throw PresetStoreError.unreadable(file.path)
        }
    }

    public func save(_ presets: [DisplayPreset]) throws {
        // Even a caller that missed an earlier load failure cannot erase a damaged
        // or future-version store. Atomic replacement protects against interrupted writes.
        _ = try load()
        try validate(presets)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Envelope(version: 1, presets: presets))
        try data.write(to: file, options: .atomic)
    }

    private func validate(_ presets: [DisplayPreset]) throws {
        guard Set(presets.map(\.id)).count == presets.count else { throw PresetStoreError.invalidPresets }
        var names: [String] = []
        for preset in presets {
            let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name == preset.name,
                  !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
                  !preset.displays.isEmpty else { throw PresetStoreError.invalidPresets }
            names.append(name)
            // Validate structural invariants using a synthetic one-to-one connection
            // set; no display hardware is read or changed by the planner.
            let live = preset.displays.enumerated().map { ConnectedDisplay(id: UInt32($0.offset + 1), state: $0.element) }
            do { _ = try RestorePlanner.plan(saved: preset.displays, connected: live) }
            catch { throw PresetStoreError.invalidPresets }
        }
    }
}
