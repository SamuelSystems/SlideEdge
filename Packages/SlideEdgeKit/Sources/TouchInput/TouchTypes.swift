import Foundation

public enum TouchPhase: Sendable, Equatable {
    case hovering
    case began
    case touching
    case ending
    case lifted
    case unknown

    /// True while the finger is in contact with the surface.
    public var isContact: Bool {
        self == .began || self == .touching
    }
}

/// One finger in a frame. Coordinates are normalized 0...1 with the origin at the bottom-left.
public struct TouchPoint: Sendable, Equatable {
    public var id: Int32
    public var x: Double
    public var y: Double
    public var velocityX: Double
    public var velocityY: Double
    public var size: Double
    public var phase: TouchPhase

    public init(id: Int32, x: Double, y: Double, velocityX: Double = 0, velocityY: Double = 0, size: Double = 0, phase: TouchPhase) {
        self.id = id
        self.x = x
        self.y = y
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.size = size
        self.phase = phase
    }
}

public struct TouchFrame: Sendable, Equatable {
    public var deviceID: UInt64
    /// Seconds, MultitouchSupport clock (monotonic).
    public var timestamp: Double
    public var frameNumber: Int32
    public var touches: [TouchPoint]

    public init(deviceID: UInt64, timestamp: Double, frameNumber: Int32, touches: [TouchPoint]) {
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.frameNumber = frameNumber
        self.touches = touches
    }
}

public enum TouchDeviceKind: String, Sendable {
    case builtInTrackpad
    case magicTrackpad
    case magicMouse

    public var title: String {
        switch self {
        case .builtInTrackpad: "Trackpad integrato"
        case .magicTrackpad: "Magic Trackpad"
        case .magicMouse: "Magic Mouse"
        }
    }
}

public struct TouchDeviceInfo: Sendable, Identifiable, Equatable {
    public var id: UInt64
    public var kind: TouchDeviceKind
    public var familyID: Int32
    /// Sensor surface in millimetres (0 when unknown).
    public var width: Double
    public var height: Double
    public var isRunning: Bool
}

public enum TouchInputStatus: Sendable, Equatable {
    case stopped
    case running
    case unavailable(String)
}
