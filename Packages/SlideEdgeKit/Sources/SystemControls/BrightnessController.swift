import CoreGraphics
import Darwin
import Foundation
import os

/// Display brightness.
///
/// Controls the main display, through DisplayServices (built-in and Apple displays) or
/// DDC/CI (other external monitors, Apple Silicon). When the main display is not
/// controllable it falls back to the built-in one. Re-evaluates when displays change.
public final class BrightnessController: @unchecked Sendable {
    public struct Status: Sendable, Equatable {
        public var isAvailable: Bool
        public var displayDescription: String

        public static let checking = Status(isAvailable: false, displayDescription: "Verifica…")
    }

    private enum Backend {
        case displayServices(CGDirectDisplayID)
        case ddc(DDCDisplay)
    }

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool

    private static let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private let queue = DispatchQueue(label: "SlideEdge.Brightness", qos: .userInitiated)
    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private let canChangeBrightness: CanChangeBrightness?
    private let onStatusChange: @Sendable (Status) -> Void
    private var displayServicesWriter: CoalescedWriter!
    /// DDC writes take tens of milliseconds and monitors dislike floods: at most 10 per second.
    private var ddcWriter: CoalescedWriter!

    // Confined to `queue`.
    private var backend: Backend?
    private var refreshScheduled = false
    /// Last known DDC level: reading a monitor is slow, so `level()` answers from here.
    private let ddcLevel = OSAllocatedUnfairLock<Double?>(initialState: nil)

    public init(onStatusChange: @escaping @Sendable (Status) -> Void) {
        let handle = dlopen(Self.path, RTLD_NOW | RTLD_LOCAL)
        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            handle.flatMap { dlsym($0, name) }.map { unsafeBitCast($0, to: T.self) }
        }
        getBrightness = symbol("DisplayServicesGetBrightness", as: GetBrightness.self)
        setBrightness = symbol("DisplayServicesSetBrightness", as: SetBrightness.self)
        canChangeBrightness = symbol("DisplayServicesCanChangeBrightness", as: CanChangeBrightness.self)
        self.onStatusChange = onStatusChange

        displayServicesWriter = CoalescedWriter(queue: queue) { [unowned self] level in
            guard case .displayServices(let display) = backend, let setBrightness else { return }
            _ = setBrightness(display, Float(level))
        }
        ddcWriter = CoalescedWriter(queue: queue, interval: 0.1) { [unowned self] level in
            guard case .ddc(let display) = backend else { return }
            display.writeBrightness(level)
        }
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        queue.async { [self] in refresh() }
    }

    /// Current level of the controlled display, nil when none is controllable.
    public func level() -> Double? {
        if let cached = ddcLevel.withLock({ $0 }) { return cached }
        return queue.sync {
            guard case .displayServices(let display) = backend else { return nil }
            return readDisplayServices(display).map(Double.init)
        }
    }

    public func setLevel(_ level: Double) {
        let level = min(max(level, 0), 1)
        ddcLevel.withLock { cached in
            if cached != nil { cached = level }
        }
        displayServicesWriter.submit(level)
        ddcWriter.submit(level)
    }

    // MARK: - Queue

    fileprivate func displaysChanged() {
        queue.async { [self] in
            // One reconfiguration fires a callback per display: refresh once.
            guard !refreshScheduled else { return }
            refreshScheduled = true
            queue.asyncAfter(deadline: .now() + 0.5) { [self] in
                refreshScheduled = false
                refresh()
            }
        }
    }

    private func refresh() {
        displayServicesWriter.discardPending()
        ddcWriter.discardPending()
        backend = chooseBackend()
        switch backend {
        case .displayServices(let display):
            ddcLevel.withLock { $0 = nil }
            let description = CGDisplayIsBuiltin(display) != 0 ? "Display integrato" : "Monitor Apple"
            onStatusChange(Status(isAvailable: true, displayDescription: description))
        case .ddc(let display):
            ddcLevel.withLock { $0 = display.readBrightness() ?? 0.5 }
            onStatusChange(Status(isAvailable: true, displayDescription: "Monitor esterno (DDC)"))
        case nil:
            ddcLevel.withLock { $0 = nil }
            onStatusChange(Status(isAvailable: false, displayDescription: "Display non controllabile"))
        }
    }

    /// Main display first (DisplayServices, then DDC), then the built-in display.
    private func chooseBackend() -> Backend? {
        let main = CGMainDisplayID()
        if canUseDisplayServices(main) { return .displayServices(main) }
        if let ddc = DDCDisplay.connect(to: main) { return .ddc(ddc) }
        if let builtIn = activeDisplays().first(where: { CGDisplayIsBuiltin($0) != 0 }), canUseDisplayServices(builtIn) {
            return .displayServices(builtIn)
        }
        return nil
    }

    private func canUseDisplayServices(_ display: CGDirectDisplayID) -> Bool {
        guard setBrightness != nil else { return false }
        return (canChangeBrightness?(display) ?? true) && readDisplayServices(display) != nil
    }

    private func readDisplayServices(_ display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard let getBrightness, getBrightness(display, &value) == 0, value.isFinite else { return nil }
        return value
    }
}

private let displayReconfigured: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
    guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
    Unmanaged<BrightnessController>.fromOpaque(userInfo).takeUnretainedValue().displaysChanged()
}
