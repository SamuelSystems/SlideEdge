import CoreGraphics
import Foundation
import os

/// Records when a key was last pressed, for palm rejection.
///
/// Privacy: the tap is listen-only and the callback stores a single timestamp.
/// It never reads the key code, characters or modifiers of the event.
/// Needs the Input Monitoring permission; `start()` returns false without it.
public final class KeyActivityMonitor: @unchecked Sendable {
    /// `ProcessInfo.systemUptime` of the last key press.
    private let lastKeyDown = OSAllocatedUnfairLock<TimeInterval?>(initialState: nil)

    // Main thread only.
    private var tap: CFMachPort?

    public init() {}

    /// Seconds since the last key press, nil when none was recorded.
    public func secondsSinceLastKeyDown() -> TimeInterval? {
        lastKeyDown.withLock { $0 }.map { ProcessInfo.processInfo.systemUptime - $0 }
    }

    @MainActor
    public var isRunning: Bool { tap.map(CGEvent.tapIsEnabled) ?? false }

    @discardableResult
    @MainActor
    public func start() -> Bool {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        self.tap = tap
        return true
    }

    @MainActor
    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        lastKeyDown.withLock { $0 = nil }
    }

    fileprivate func handle(_ type: CGEventType) {
        switch type {
        case .keyDown:
            let now = ProcessInfo.processInfo.systemUptime
            lastKeyDown.withLock { $0 = now }
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Delivered on the main run loop (see start).
            MainActor.assumeIsolated {
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
        default:
            break
        }
    }
}

private let keyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    if let userInfo {
        Unmanaged<KeyActivityMonitor>.fromOpaque(userInfo).takeUnretainedValue().handle(type)
    }
    // Listen-only: the return value is ignored, the event is never altered.
    return Unmanaged.passUnretained(event)
}
