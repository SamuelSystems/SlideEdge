import CoreGraphics
import Darwin
import Foundation
import os

/// Freezes (and optionally hides) the pointer while a slide is in progress, so the finger on the edge does not also move the cursor.
///
/// macOS offers no reliable way for a background app to stop the pointer, so several layers are combined:
/// - `CGAssociateMouseAndMouseCursorPosition` decouples the pointer from the trackpad (honoured for some apps only);
/// - an active event tap (needs Accessibility) drops pointer-move events and warps the pointer back;
/// - `enforce()`, called on every touch frame, warps the pointer back even if the other two are ignored.
/// The tap is created once and enabled only while locked, so it costs nothing at rest.
public final class CursorLock: @unchecked Sendable {
    private static let log = Logger(subsystem: "io.github.samuelsystems.slideedge", category: "cursor")

    /// Read from any thread by `enforce()`.
    private let lockedPosition = OSAllocatedUnfairLock<CGPoint?>(initialState: nil)

    // Main thread only.
    private var hidden = false
    private var tap: CFMachPort?
    private var tapCreationFailed = false

    public init() {}

    public var isLocked: Bool { lockedPosition.withLock { $0 != nil } }

    /// Locks the pointer at `position` (sampled when the finger landed), or where it is now.
    @MainActor
    public func lock(at position: CGPoint? = nil, hidingCursor: Bool) {
        guard !isLocked, let position = position ?? CGEvent(source: nil)?.location else { return }
        lockedPosition.withLock { $0 = position }
        CGWarpMouseCursorPosition(position)
        let associate = CGAssociateMouseAndMouseCursorPosition(0)

        let tap = tap ?? makeTap()
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        Self.log.debug("lock at (\(Int(position.x)), \(Int(position.y))): associate=\(associate.rawValue) tap=\(tap != nil)")
        if hidingCursor { hide() }
    }

    /// Hides the pointer until `unlock()`. No effect when not locked.
    @MainActor
    public func hide() {
        guard isLocked, !hidden else { return }
        Self.allowCursorControlInBackground()
        let result = CGDisplayHideCursor(CGMainDisplayID())
        hidden = result == .success
        Self.log.debug("hide: result=\(result.rawValue)")
    }

    @MainActor
    public func unlock() {
        guard let position = lockedPosition.withLock({ value in defer { value = nil }; return value }) else { return }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        // Undo any movement that slipped through, then re-associate: associating
        // right after a warp also cancels the warp's short event-suppression delay.
        let before = CGEvent(source: nil)?.location ?? .zero
        CGWarpMouseCursorPosition(position)
        CGAssociateMouseAndMouseCursorPosition(1)
        Self.log.debug("unlock: pointer was (\(Int(before.x)), \(Int(before.y))), restored to (\(Int(position.x)), \(Int(position.y)))")
        if hidden {
            CGDisplayShowCursor(CGMainDisplayID())
            hidden = false
        }
    }

    /// Puts the pointer back on the locked position. Safe to call from any thread, e.g. on every touch frame.
    public func enforce() {
        guard let position = lockedPosition.withLock({ $0 }) else { return }
        guard let current = CGEvent(source: nil)?.location, current != position else { return }
        CGWarpMouseCursorPosition(position)
    }

    /// Returns whether the event passes through.
    fileprivate func shouldPass(_ type: CGEventType) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if isLocked, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        default:
            guard isLocked else { return true }
            enforce()
            return false
        }
    }

    /// nil without Accessibility permission: the lock then relies on the other layers.
    @MainActor
    private func makeTap() -> CFMachPort? {
        guard !tapCreationFailed else { return nil }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: cursorTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            tapCreationFailed = true
            Self.log.error("cursor event tap could not be created (Accessibility not granted?)")
            return nil
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        // The main run loop is fine: while locked every event is dropped anyway, and when unlocked the tap is off.
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        self.tap = tap
        return tap
    }

    // MARK: - Private API

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    @MainActor private static var backgroundCursorControlEnabled = false

    /// `CGDisplayHideCursor` only works for the frontmost app unless the connection
    /// sets the private "SetsCursorInBackground" property. If it is missing, hiding is skipped silently.
    @MainActor
    private static func allowCursorControlInBackground() {
        guard !backgroundCursorControlEnabled else { return }
        backgroundCursorControlEnabled = true
        guard
            let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
            let mainSymbol = dlsym(handle, "CGSMainConnectionID"),
            let setSymbol = dlsym(handle, "CGSSetConnectionProperty")
        else {
            log.error("CGSSetConnectionProperty not available")
            return
        }
        let connection = unsafeBitCast(mainSymbol, to: MainConnectionID.self)()
        let setProperty = unsafeBitCast(setSymbol, to: SetConnectionProperty.self)
        let result = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        log.notice("SetsCursorInBackground connection=\(connection) result=\(result)")
    }
}

private let cursorTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let pass = Unmanaged<CursorLock>.fromOpaque(userInfo).takeUnretainedValue().shouldPass(type)
    return pass ? Unmanaged.passUnretained(event) : nil
}
