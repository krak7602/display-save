import Foundation

public enum RestorePlanningError: LocalizedError {
    case invalidSnapshot
    case noMatchingDisplays

    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot:
            return "This layout has invalid or duplicate display information. Save a new layout in Display Save."
        case .noMatchingDisplays:
            return "None of this layout’s displays can be identified. Connect a saved display and try again. No settings were changed."
        }
    }
}

public enum RestorePlanner {
    public static func plan(saved: [DisplayState], connected: [ConnectedDisplay]) throws -> RestorePlan {
        guard !saved.isEmpty,
              Set(saved.map(\.id)).count == saved.count,
              Set(connected.map(\.id)).count == connected.count,
              Set(connected.map { $0.state.id }).count == connected.count,
              saved.allSatisfy(validState) else {
            throw RestorePlanningError.invalidSnapshot
        }

        var matches: [String: ConnectedDisplay] = [:]
        var used = Set<UInt32>()
        var warnings: [String] = []
        for display in saved {
            if let live = connected.first(where: {
                $0.state.id == display.id && hardwareMatches(display.identity, $0.state.identity)
            }) {
                matches[display.id] = live
                used.insert(live.id)
            }
        }
        // Match hardware only if it is unique on BOTH sides. Never guess between
        // identical monitors with absent serial numbers, even if one remains unused.
        for display in saved where matches[display.id] == nil {
            let candidates = connected.filter { hardwareMatches(display.identity, $0.state.identity) }
            guard candidates.count == 1, let live = candidates.first, !used.contains(live.id),
                  saved.filter({ hardwareMatches($0.identity, live.state.identity) }).count == 1 else {
                continue
            }
            matches[display.id] = live
            used.insert(live.id)
            warnings.append("\(display.name) was identified by its hardware because its macOS display ID changed.")
        }
        guard !matches.isEmpty else { throw RestorePlanningError.noMatchingDisplays }

        for display in saved where matches[display.id] == nil {
            warnings.append("\(display.name) is disconnected or cannot be identified; it was skipped.")
        }

        var planned = saved.compactMap { display -> PlannedDisplay? in
            guard let live = matches[display.id] else { return nil }
            return PlannedDisplay(displayID: live.id, saved: display, x: display.x, y: display.y,
                                  mirrorSourceID: display.mirrorSourceUUID.flatMap { matches[$0]?.id })
        }
        // A missing mirror source does not make its connected followers unusable.
        // Promote one follower; keep any remaining members of that group mirrored.
        var promotedSources: [String: UInt32] = [:]
        for index in planned.indices {
            guard let source = planned[index].saved.mirrorSourceUUID, matches[source] == nil else { continue }
            let name = planned[index].saved.name
            if let promoted = promotedSources[source] {
                planned[index].mirrorSourceID = promoted
            } else {
                promotedSources[source] = planned[index].displayID
                planned[index].mirrorSourceID = nil
                warnings.append("\(name) will be used independently because its mirror source is missing.")
            }
        }

        // A mirror source must be a root, never a follower or the same display.
        let roots = Set(planned.filter { $0.mirrorSourceID == nil }.map(\.displayID))
        guard planned.allSatisfy({ $0.mirrorSourceID == nil || roots.contains($0.mirrorSourceID!) }) else {
            throw RestorePlanningError.invalidSnapshot
        }
        let primary = planned.first { $0.saved.isMain && $0.mirrorSourceID == nil }
            ?? planned.first { item in
                item.mirrorSourceID == nil && connected.contains { $0.id == item.displayID && $0.state.isMain }
            }
            ?? planned.first { $0.mirrorSourceID == nil }
        guard let primary else { throw RestorePlanningError.invalidSnapshot }
        if !primary.saved.isMain {
            warnings.append("The saved main display is missing; \(primary.saved.name) will be the main display.")
        }
        for index in planned.indices {
            planned[index].x -= primary.x
            planned[index].y -= primary.y
        }

        // Keep unsaved displays usable, rather than disabling them or allowing
        // their old (0,0) origin to steal the restored layout’s primary display.
        let extras = connected.filter { !used.contains($0.id) }
        let liveByUUID = Dictionary(uniqueKeysWithValues: connected.map { ($0.state.id, $0.id) })
        var nextX = planned.filter { $0.mirrorSourceID == nil }
            .map { $0.x + $0.saved.mode.width }.max() ?? 0
        for live in extras where live.state.mirrorSourceUUID == nil {
            planned.append(PlannedDisplay(displayID: live.id, saved: live.state, x: nextX, y: 0, mirrorSourceID: nil))
            nextX += live.state.mode.width
        }
        for live in extras where live.state.mirrorSourceUUID != nil {
            let sourceID = live.state.mirrorSourceUUID.flatMap { liveByUUID[$0] }
            if let source = planned.first(where: { $0.displayID == sourceID && $0.mirrorSourceID == nil }) {
                planned.append(PlannedDisplay(displayID: live.id, saved: live.state,
                                              x: source.x, y: source.y, mirrorSourceID: source.displayID))
            } else {
                planned.append(PlannedDisplay(displayID: live.id, saved: live.state, x: nextX, y: 0, mirrorSourceID: nil))
                nextX += live.state.mode.width
            }
        }
        if !extras.isEmpty {
            warnings.append("\(extras.count) connected display\(extras.count == 1 ? " is" : "s are") not in this layout and will remain available.")
        }
        return RestorePlan(displays: planned, warnings: warnings)
    }

    private static func hardwareMatches(_ saved: DisplayIdentity, _ live: DisplayIdentity) -> Bool {
        guard saved.vendor == live.vendor, saved.model == live.model, saved.isBuiltIn == live.isBuiltIn else { return false }
        if saved.serial != 0 && live.serial != 0 { return saved.serial == live.serial }
        return true
    }

    private static func validState(_ state: DisplayState) -> Bool {
        !state.id.isEmpty && state.mode.width > 0 && state.mode.height > 0
            && state.mode.pixelWidth > 0 && state.mode.pixelHeight > 0
            && state.mode.refreshRate.isFinite && state.mode.refreshRate >= 0
            && [0, 90, 180, 270].contains(state.rotation)
            && state.x >= Int(Int32.min) / 2 && state.x <= Int(Int32.max) / 2
            && state.y >= Int(Int32.min) / 2 && state.y <= Int(Int32.max) / 2
            && state.mirrorSourceUUID != state.id
    }
}
