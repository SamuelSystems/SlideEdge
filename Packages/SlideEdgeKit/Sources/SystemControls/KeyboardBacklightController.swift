import CCoreBrightness
import Foundation

/// Keyboard backlight level, through CoreBrightness.
public final class KeyboardBacklightController: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SlideEdge.KeyboardBacklight", qos: .userInitiated)
    private let backlight: SEKeyboardBacklight?
    private var writer: CoalescedWriter!

    public init() {
        backlight = SEKeyboardBacklight.connect()
        writer = CoalescedWriter(queue: queue) { [backlight] level in
            _ = backlight?.setBrightness(Float(level))
        }
    }

    public var isAvailable: Bool { backlight != nil }

    public func level() -> Double? {
        queue.sync { backlight.map { Double($0.brightness) } }
    }

    public func setLevel(_ level: Double) {
        writer.submit(min(max(level, 0), 1))
    }
}
