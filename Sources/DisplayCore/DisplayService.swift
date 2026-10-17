import AppKit
import ColorSync
import CoreGraphics
import DisplayHardware
import Foundation

public struct RestoreOutcome: Sendable {
    public let warnings: [String]

    public init(warnings: [String]) {
        self.warnings = warnings
    }
}

private struct DisplayServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
public final class DisplayService {
    private var isRestoring = false

    public init() {}

    public func capture() throws -> [ConnectedDisplay] {
        let ids = try onlineDisplayIDs()
        var identities: [CGDirectDisplayID: DisplayIdentity] = [:]
        for id in ids {
            identities[id] = try identity(for: id)
        }
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return try ids.map { id in
            guard let identity = identities[id], let mode = CGDisplayCopyDisplayMode(id) else {
                throw DisplayServiceError(message: "macOS did not provide the current mode for display \(id). Wake or reconnect the display, then try again; an incomplete layout cannot be saved.")
            }
            let sourceID = CGDisplayMirrorsDisplay(id)
            if sourceID != kCGNullDirectDisplay && identities[sourceID] == nil {
                throw DisplayServiceError(message: "The mirror source for display \(id) changed while reading the layout. Wait for the displays to settle and try again.")
            }
            let bounds = CGDisplayBounds(id)
            let name = names[id] ?? (identity.isBuiltIn ? "Built-in Display" : "Display \(identity.vendor):\(identity.model) (\(id))")
            return ConnectedDisplay(
                id: id,
                state: DisplayState(
                    identity: identity,
                    name: name,
                    mode: describe(mode),
                    x: Int(bounds.origin.x.rounded()),
                    y: Int(bounds.origin.y.rounded()),
                    rotation: normalizedRotation(CGDisplayRotation(id)),
                    isMain: CGDisplayIsMain(id) != 0,
                    mirrorSourceUUID: identities[sourceID]?.uuid
                )
            )
        }
    }

    public func restore(_ preset: DisplayPreset) async throws -> RestoreOutcome {
        guard !isRestoring else {
            throw DisplayServiceError(message: "A display layout is already being applied. Wait for it to finish before applying another layout.")
        }
        isRestoring = true
        defer { isRestoring = false }
        try Task.checkCancellation()
        let before = try capture()
        let plan = try RestorePlanner.plan(saved: preset.displays, connected: before)
        let originalByID = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        var warnings = plan.warnings
        let rotating = Set(plan.displays.filter {
            originalByID[$0.displayID]?.state.rotation != $0.saved.rotation
        }.map(\.displayID))
        for display in plan.displays {
            guard [0, 90, 180, 270].contains(display.saved.rotation) else {
                throw DisplayServiceError(message: "\(display.saved.name) has an unsupported saved rotation of \(display.saved.rotation)°. Save a layout with a standard quarter-turn orientation in System Settings.")
            }
            guard Int32(exactly: display.x) != nil, Int32(exactly: display.y) != nil else {
                throw DisplayServiceError(message: "The saved position of \(display.saved.name) is outside the range supported by macOS. Arrange the displays in System Settings and save a new layout.")
            }
        }
        if !rotating.isEmpty && !DSRotationAvailable() {
            throw DisplayServiceError(message: "This layout requires rotation, but this macOS version does not expose the MonitorPanel rotation interface. Set the orientation in System Settings, then apply the layout again.")
        }

        // Only detach existing followers whose topology or orientation must change.
        // Moving an independent root does not require dismantling its mirror set.
        let detach = plan.displays.filter { planned in
            let currentSource = CGDisplayMirrorsDisplay(planned.displayID)
            return currentSource != kCGNullDirectDisplay &&
                (currentSource != (planned.mirrorSourceID ?? kCGNullDirectDisplay) ||
                 rotating.contains(planned.displayID) || rotating.contains(currentSource))
        }
        if !detach.isEmpty {
            try ensureConnected(plan.displays, originalByID: originalByID)
            try transaction(option: .forSession) { config in
                for display in detach {
                    try check(CGConfigureDisplayMirrorOfDisplay(config, display.displayID, kCGNullDirectDisplay), operation: "Stop mirroring \(display.saved.name)")
                }
            }
            try await waitUntil(seconds: 5, failure: "macOS did not separate the affected mirror displays. Change mirroring in System Settings and try again.") {
                try self.ensureConnected(plan.displays, originalByID: originalByID)
                return detach.allSatisfy { CGDisplayMirrorsDisplay($0.displayID) == kCGNullDirectDisplay }
            }
        }

        for display in plan.displays where rotating.contains(display.displayID) {
            try Task.checkCancellation()
            try ensureConnected(plan.displays, originalByID: originalByID)
            guard DSSetRotation(display.displayID, Int32(display.saved.rotation)) else {
                let detail = String(cString: DSRotationLastError())
                throw DisplayServiceError(message: "Could not rotate \(display.saved.name): \(detail)")
            }
            try await waitUntil(seconds: 10, failure: "\(display.saved.name) did not reach \(display.saved.rotation)° after 10 seconds. The display or driver may not support this orientation. Check System Settings before trying again.") {
                try self.ensureConnected(plan.displays, originalByID: originalByID)
                return self.normalizedRotation(CGDisplayRotation(display.displayID)) == display.saved.rotation
            }
        }

        // Rotation can invalidate all previously enumerated mode objects. Enumerate
        // now, matching characteristics rather than transient driver mode indexes.
        try ensureConnected(plan.displays, originalByID: originalByID)
        var modes: [CGDirectDisplayID: CGDisplayMode] = [:]
        var requestedModes: [CGDirectDisplayID: DisplayMode] = [:]
        for display in plan.displays {
            guard let current = CGDisplayCopyDisplayMode(display.displayID) else {
                throw DisplayServiceError(message: "macOS stopped reporting a mode for \(display.saved.name). Wake or reconnect it, then try again.")
            }
            let saved = display.saved.mode
            if describe(current).matches(saved) {
                modes[display.displayID] = current
                requestedModes[display.displayID] = saved
                continue
            }
            let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
            let available = CGDisplayCopyAllDisplayModes(display.displayID, options) as? [CGDisplayMode] ?? []
            if let exact = available.first(where: { $0.isUsableForDesktopGUI() && describe($0).matches(saved) }) {
                modes[display.displayID] = exact
                requestedModes[display.displayID] = saved
            } else {
                // Do not guess a nearest mode: that can change scaling, refresh,
                // or scan characteristics and leave a screen unusable.
                modes[display.displayID] = current
                warnings.append("\(display.saved.name): saved mode \(modeLabel(saved)) is unavailable; keeping the current mode \(modeLabel(describe(current))). Choose the desired mode in System Settings and save the layout again.")
            }
        }

        try transaction(option: .forSession) { config in
            try ensureConnected(plan.displays, originalByID: originalByID)
            // Configure roots first so followers cannot change their source's mode
            // after its explicit choice has been made in an earlier transaction.
            let ordered = plan.displays.filter { $0.mirrorSourceID == nil } + plan.displays.filter { $0.mirrorSourceID != nil }
            for display in ordered {
                try Task.checkCancellation()
                if let mode = modes[display.displayID] {
                    try check(CGConfigureDisplayWithDisplayMode(config, display.displayID, mode, nil), operation: "Set the display mode for \(display.saved.name)")
                }
            }
            for display in plan.displays where display.mirrorSourceID == nil {
                try check(CGConfigureDisplayOrigin(config, display.displayID, Int32(display.x), Int32(display.y)), operation: "Position \(display.saved.name)")
            }
            // Setting an origin on a mirror follower implicitly unmirrors it.
            // Apply mirror edges last, and never configure follower origins.
            for display in plan.displays {
                if let source = display.mirrorSourceID {
                    try check(CGConfigureDisplayMirrorOfDisplay(config, display.displayID, source), operation: "Mirror \(display.saved.name)")
                }
            }
        }

        let verified = try await verify(plan: plan, originalByID: originalByID, requestedModes: requestedModes)
        warnings.append(contentsOf: verified)
        return RestoreOutcome(warnings: unique(warnings))
    }

    public func keep() throws {
        guard !isRestoring else {
            throw DisplayServiceError(message: "Wait for the display layout to finish applying before keeping it.")
        }
        let current = try capture()
        let idsByUUID = Dictionary(uniqueKeysWithValues: current.map { ($0.state.identity.uuid, $0.id) })
        // The current SDK has no CGDisplaySaveCurrentConfiguration API. Re-submit
        // the live snapshot through the public permanent-configuration transaction.
        try transaction(option: .permanently) { config in
            for display in current {
                guard let mode = CGDisplayCopyDisplayMode(display.id) else {
                    throw DisplayServiceError(message: "\(display.state.name) disconnected before the layout could be kept. Reconnect it and try again.")
                }
                try check(CGConfigureDisplayWithDisplayMode(config, display.id, mode, nil), operation: "Keep the mode for \(display.state.name)")
            }
            for display in current where display.state.mirrorSourceUUID == nil {
                guard let x = Int32(exactly: display.state.x), let y = Int32(exactly: display.state.y) else {
                    throw DisplayServiceError(message: "The current display position is outside macOS's supported coordinate range.")
                }
                try check(CGConfigureDisplayOrigin(config, display.id, x, y), operation: "Keep the position of \(display.state.name)")
            }
            for display in current {
                if let sourceUUID = display.state.mirrorSourceUUID {
                    guard let source = idsByUUID[sourceUUID] else {
                        throw DisplayServiceError(message: "A mirror source disconnected before the layout could be kept. Reconnect it and try again.")
                    }
                    try check(CGConfigureDisplayMirrorOfDisplay(config, display.id, source), operation: "Keep mirroring for \(display.state.name)")
                }
            }
        }
    }

    private func onlineDisplayIDs() throws -> [CGDirectDisplayID] {
        // Re-read the count to detect a display appearing between the two calls.
        for _ in 0..<3 {
            var count: UInt32 = 0
            try check(CGGetOnlineDisplayList(0, nil, &count), operation: "Read the connected display count")
            guard count > 0 else {
                throw DisplayServiceError(message: "No online displays were reported. Wake or reconnect a display and try again.")
            }
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            var written: UInt32 = 0
            try check(CGGetOnlineDisplayList(count, &ids, &written), operation: "Read the connected displays")
            var latestCount: UInt32 = 0
            try check(CGGetOnlineDisplayList(0, nil, &latestCount), operation: "Confirm the connected display count")
            if latestCount == written && written <= count {
                return Array(ids.prefix(Int(written)))
            }
        }
        throw DisplayServiceError(message: "Displays are still connecting or disconnecting. Wait for the layout to settle and try again.")
    }

    private func identity(for id: CGDirectDisplayID) throws -> DisplayIdentity {
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(id) else {
            throw DisplayServiceError(message: "macOS did not provide a persistent identity for display \(id). Reconnect the display and try again; a temporary display ID cannot safely identify a saved layout.")
        }
        let uuid = unmanaged.takeRetainedValue()
        return DisplayIdentity(
            uuid: CFUUIDCreateString(nil, uuid) as String,
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            serial: CGDisplaySerialNumber(id),
            isBuiltIn: CGDisplayIsBuiltin(id) != 0
        )
    }

    private func describe(_ mode: CGDisplayMode) -> DisplayMode {
        DisplayMode(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate, ioFlags: mode.ioFlags)
    }

    private func normalizedRotation(_ degrees: Double) -> Int {
        let rounded = Int(degrees.rounded())
        return ((rounded % 360) + 360) % 360
    }

    private func modeLabel(_ mode: DisplayMode) -> String {
        let refresh = mode.refreshRate == 0 ? "system refresh" : String(format: "%.2f Hz", mode.refreshRate)
        return "\(mode.width)×\(mode.height) (\(mode.pixelWidth)×\(mode.pixelHeight) pixels, \(refresh))"
    }

    private func check(_ result: CGError, operation: String) throws {
        guard result == .success else {
            throw DisplayServiceError(message: "\(operation) failed (CoreGraphics error \(result.rawValue)). Close full-screen apps, check the display connection and available settings in System Settings, then try again.")
        }
    }

    private func transaction(option: CGConfigureOption, _ configure: (CGDisplayConfigRef) throws -> Void) throws {
        try Task.checkCancellation()
        var reference: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&reference), operation: "Begin the display configuration")
        guard let config = reference else {
            throw DisplayServiceError(message: "macOS did not create a display configuration transaction. Try again after closing full-screen apps.")
        }
        var consumed = false
        defer {
            if !consumed { CGCancelDisplayConfiguration(config) }
        }
        try configure(config)
        try Task.checkCancellation()
        // CoreGraphics consumes the transaction even when completion fails.
        // Do not pass the now-invalid pointer to CGCancelDisplayConfiguration.
        consumed = true
        try check(CGCompleteDisplayConfiguration(config, option), operation: "Apply the display configuration")
    }

    private func ensureConnected(_ planned: [PlannedDisplay], originalByID: [CGDirectDisplayID: ConnectedDisplay]) throws {
        let online = Set(try onlineDisplayIDs())
        for display in planned {
            guard online.contains(display.displayID),
                  let original = originalByID[display.displayID],
                  try identity(for: display.displayID).uuid == original.state.identity.uuid else {
                throw DisplayServiceError(message: "\(display.saved.name) disconnected or changed identity while the layout was being applied. Reconnect it and try again.")
            }
        }
    }

    private func waitUntil(seconds: Double, failure: String, condition: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(Int64(seconds * 1_000)))
        while true {
            try Task.checkCancellation()
            if try condition() { return }
            if ContinuousClock.now >= deadline { throw DisplayServiceError(message: failure) }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func verify(plan: RestorePlan, originalByID: [CGDirectDisplayID: ConnectedDisplay], requestedModes: [CGDirectDisplayID: DisplayMode]) async throws -> [String] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while true {
            try Task.checkCancellation()
            try ensureConnected(plan.displays, originalByID: originalByID)
            let live = Dictionary(uniqueKeysWithValues: try capture().map { ($0.id, $0.state) })
            var failures: [String] = []
            var warnings: [String] = []
            for display in plan.displays {
                guard let state = live[display.displayID] else {
                    throw DisplayServiceError(message: "\(display.saved.name) disconnected while verifying the restored layout.")
                }
                if state.rotation != display.saved.rotation {
                    failures.append("\(display.saved.name) is at \(state.rotation)°, not the requested \(display.saved.rotation)°")
                }
                let expectedSource = display.mirrorSourceID.flatMap { originalByID[$0]?.state.identity.uuid }
                if state.mirrorSourceUUID != expectedSource {
                    failures.append("\(display.saved.name) did not accept the requested mirroring setting")
                }
                if let requested = requestedModes[display.displayID], !state.mode.matches(requested) {
                    warnings.append("\(display.saved.name): macOS selected \(modeLabel(state.mode)) instead of \(modeLabel(requested)). The display driver or mirror group may require a different mode.")
                }
                if display.mirrorSourceID == nil && (state.x != display.x || state.y != display.y) {
                    warnings.append("\(display.saved.name): macOS adjusted the position to (\(state.x), \(state.y)) from (\(display.x), \(display.y)) to fit the connected display arrangement.")
                }
                if display.mirrorSourceID == nil && display.x == 0 && display.y == 0 && !state.isMain {
                    warnings.append("macOS kept a different display as the main display. Choose the main display in System Settings if needed.")
                }
            }
            if failures.isEmpty && warnings.isEmpty { return [] }
            if ContinuousClock.now >= deadline {
                if !failures.isEmpty {
                    throw DisplayServiceError(message: "The restored layout could not be verified: \(failures.joined(separator: "; ")). Check System Settings and the display connections before trying again.")
                }
                return warnings
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
