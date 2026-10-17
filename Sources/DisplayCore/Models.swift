import Foundation

public struct DisplayIdentity: Codable, Equatable, Sendable {
    public var uuid: String
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var isBuiltIn: Bool

    public init(uuid: String, vendor: UInt32, model: UInt32, serial: UInt32, isBuiltIn: Bool) {
        self.uuid = uuid
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.isBuiltIn = isBuiltIn
    }
}

public struct DisplayMode: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double
    public var ioFlags: UInt32

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double, ioFlags: UInt32) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.ioFlags = ioFlags
    }

    public func matches(_ other: DisplayMode) -> Bool {
        // Ignore transient "valid", "safe", "default" and driver bookkeeping flags.
        // Interlacing, stretching and television output change the actual output mode.
        let outputFlags: UInt32 = 0x00000040 | 0x00000800 | 0x00100000
        let refreshMatches = refreshRate == 0 || other.refreshRate == 0
            ? refreshRate == other.refreshRate
            : abs(refreshRate - other.refreshRate) < 0.6
        return width == other.width && height == other.height
            && pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight
            && refreshMatches && (ioFlags & outputFlags) == (other.ioFlags & outputFlags)
    }
}

public struct DisplayState: Codable, Equatable, Identifiable, Sendable {
    public var identity: DisplayIdentity
    public var name: String
    public var mode: DisplayMode
    public var x: Int
    public var y: Int
    public var rotation: Int
    public var isMain: Bool
    public var mirrorSourceUUID: String?
    public var id: String { identity.uuid }

    public init(identity: DisplayIdentity, name: String, mode: DisplayMode, x: Int, y: Int, rotation: Int,
                isMain: Bool, mirrorSourceUUID: String?) {
        self.identity = identity
        self.name = name
        self.mode = mode
        self.x = x
        self.y = y
        self.rotation = rotation
        self.isMain = isMain
        self.mirrorSourceUUID = mirrorSourceUUID
    }
}

public struct DisplayPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var displays: [DisplayState]

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), displays: [DisplayState]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.displays = displays
    }
}

public struct ConnectedDisplay: Equatable, Sendable {
    public var id: UInt32
    public var state: DisplayState

    public init(id: UInt32, state: DisplayState) {
        self.id = id
        self.state = state
    }
}

public struct PlannedDisplay: Equatable, Sendable {
    public var displayID: UInt32
    public var saved: DisplayState
    public var x: Int
    public var y: Int
    public var mirrorSourceID: UInt32?

    public init(displayID: UInt32, saved: DisplayState, x: Int, y: Int, mirrorSourceID: UInt32?) {
        self.displayID = displayID
        self.saved = saved
        self.x = x
        self.y = y
        self.mirrorSourceID = mirrorSourceID
    }
}

public struct RestorePlan: Equatable, Sendable {
    public var displays: [PlannedDisplay]
    public var warnings: [String]

    public init(displays: [PlannedDisplay], warnings: [String]) {
        self.displays = displays
        self.warnings = warnings
    }
}
