import CMultitouch
import Foundation
import IOKit

/// Reads raw touches from every multitouch device and follows hot-plug.
///
/// All mutable state is confined to `queue`. Frame handlers are called on
/// MultitouchSupport's private thread and must return quickly.
public final class TouchInputManager: @unchecked Sendable {
    public typealias FrameHandler = @Sendable (TouchFrame) -> Void
    public typealias DevicesHandler = @Sendable ([TouchDeviceInfo], TouchInputStatus) -> Void

    private let queue = DispatchQueue(label: "SlideEdge.TouchInput", qos: .userInteractive)
    private let library: Result<MultitouchLibrary, MultitouchLibrary.LoadError>
    private let onFrame: FrameHandler
    private let onDevicesChanged: DevicesHandler

    private var wantsRunning = false
    private var includeMagicMouse = false
    private var deviceList: CFMutableArray?
    private var contexts: [DeviceContext] = []
    /// Stopped devices kept alive briefly: MultitouchSupport may still be inside a callback.
    private var retired: [(CFMutableArray?, [DeviceContext])] = []
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var rebuildPending = false

    public init(onFrame: @escaping FrameHandler, onDevicesChanged: @escaping DevicesHandler) {
        self.library = MultitouchLibrary.load()
        self.onFrame = onFrame
        self.onDevicesChanged = onDevicesChanged
    }

    public func start(includeMagicMouse: Bool) {
        queue.async { [self] in
            self.includeMagicMouse = includeMagicMouse
            guard !wantsRunning else { return rebuild() }
            wantsRunning = true
            installHotplugNotifications()
            startDevices()
        }
    }

    public func stop() {
        queue.async { [self] in
            guard wantsRunning else { return }
            wantsRunning = false
            stopDevices()
            removeHotplugNotifications()
            onDevicesChanged([], .stopped)
        }
    }

    /// Recreates every device, e.g. after wake from sleep when devices often stop sending frames.
    public func restart(after delay: TimeInterval = 0) {
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            guard wantsRunning else { return }
            rebuild()
        }
    }

    // MARK: - Devices (queue)

    private func startDevices() {
        let library: MultitouchLibrary
        switch self.library {
        case .success(let loaded): library = loaded
        case .failure(let error): return onDevicesChanged([], .unavailable(error.message))
        }

        guard let list = library.createList()?.takeRetainedValue() else {
            return onDevicesChanged([], .unavailable("Nessun dispositivo multitouch"))
        }
        deviceList = list

        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = MTDeviceRef(mutating: raw)
            var info = describe(device, index: index, library: library)
            if info.kind == .magicMouse && !includeMagicMouse { continue }

            let context = DeviceContext(device: device, deviceID: info.id, sink: onFrame)
            library.register(device, frameCallback, Unmanaged.passUnretained(context).toOpaque())
            info.isRunning = library.start(device, 0) == 0
            context.info = info
            contexts.append(context)
        }
        onDevicesChanged(contexts.map(\.info), .running)
    }

    private func stopDevices() {
        guard case .success(let library) = library else { return }
        for context in contexts {
            library.unregister(context.device, frameCallback)
            _ = library.stop(context.device)
        }
        retired.append((deviceList, contexts))
        deviceList = nil
        contexts = []
        queue.asyncAfter(deadline: .now() + 1) { [self] in
            if !retired.isEmpty { retired.removeFirst() }
        }
    }

    private func rebuild() {
        stopDevices()
        startDevices()
    }

    private func describe(_ device: MTDeviceRef, index: CFIndex, library: MultitouchLibrary) -> TouchDeviceInfo {
        var familyID: Int32 = 0
        _ = library.getFamilyID?(device, &familyID)

        var deviceID: UInt64 = 0
        if library.getDeviceID?(device, &deviceID) != 0 || deviceID == 0 {
            deviceID = UInt64(index + 1)
        }

        // Reported in hundredths of a millimetre.
        var width: Int32 = 0
        var height: Int32 = 0
        _ = library.getDimensions?(device, &width, &height)

        let kind: TouchDeviceKind
        if library.isBuiltIn?(device) == true {
            kind = .builtInTrackpad
        } else if familyID == 112 || familyID == 113 || height > width {
            // The Magic Mouse surface is the only one taller than wide.
            kind = .magicMouse
        } else {
            kind = .magicTrackpad
        }

        return TouchDeviceInfo(
            id: deviceID,
            kind: kind,
            familyID: familyID,
            width: Double(width) / 100,
            height: Double(height) / 100,
            isRunning: false
        )
    }

    // MARK: - Hot-plug (queue)

    private func installHotplugNotifications() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, queue)
        notifyPort = port

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"), hotplugCallback, refcon, &iterator
            )
            guard result == KERN_SUCCESS else { continue }
            // Draining arms the notification; the devices already present are handled by startDevices().
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    private func removeHotplugNotifications() {
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
        notifyPort = nil
    }

    fileprivate func deviceSetChanged(_ iterator: io_iterator_t) {
        Self.drain(iterator)
        // Plugging a device in fires several services; coalesce them into one rebuild.
        guard wantsRunning, !rebuildPending else { return }
        rebuildPending = true
        queue.asyncAfter(deadline: .now() + 0.75) { [self] in
            rebuildPending = false
            if wantsRunning { rebuild() }
        }
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }
}

// MARK: - C callbacks

private final class DeviceContext: @unchecked Sendable {
    let device: MTDeviceRef
    let deviceID: UInt64
    let sink: TouchInputManager.FrameHandler
    var info: TouchDeviceInfo!

    init(device: MTDeviceRef, deviceID: UInt64, sink: @escaping TouchInputManager.FrameHandler) {
        self.device = device
        self.deviceID = deviceID
        self.sink = sink
    }

    func deliver(_ touches: UnsafePointer<MTTouch>?, count: Int32, timestamp: Double, frame: Int32) {
        var points: [TouchPoint] = []
        if let touches, count > 0 {
            let count = min(Int(count), 20)
            points.reserveCapacity(count)
            for touch in UnsafeBufferPointer(start: touches, count: count) {
                let x = Double(touch.normalizedVector.position.x)
                let y = Double(touch.normalizedVector.position.y)
                // A struct layout change in a future macOS shows up as garbage values: drop them.
                guard x.isFinite, y.isFinite, (-0.05...1.05).contains(x), (-0.05...1.05).contains(y) else { continue }
                points.append(TouchPoint(
                    id: touch.pathIndex,
                    x: min(max(x, 0), 1),
                    y: min(max(y, 0), 1),
                    velocityX: Double(touch.normalizedVector.velocity.x),
                    velocityY: Double(touch.normalizedVector.velocity.y),
                    size: Double(touch.zTotal),
                    phase: TouchPhase(rawState: touch.state)
                ))
            }
        }
        sink(TouchFrame(deviceID: deviceID, timestamp: timestamp, frameNumber: frame, touches: points))
    }
}

private let frameCallback: MTContactFrameCallbackRefcon = { _, touches, count, timestamp, frame, refcon in
    guard let refcon else { return }
    Unmanaged<DeviceContext>.fromOpaque(refcon).takeUnretainedValue()
        .deliver(touches, count: count, timestamp: timestamp, frame: frame)
}

private let hotplugCallback: IOServiceMatchingCallback = { refcon, iterator in
    guard let refcon else { return }
    Unmanaged<TouchInputManager>.fromOpaque(refcon).takeUnretainedValue().deviceSetChanged(iterator)
}

extension TouchPhase {
    init(rawState: Int32) {
        switch rawState {
        case Int32(MTTouchStateStartInRange), Int32(MTTouchStateHoverInRange): self = .hovering
        case Int32(MTTouchStateMakeTouch): self = .began
        case Int32(MTTouchStateTouching): self = .touching
        case Int32(MTTouchStateBreakTouch): self = .ending
        case Int32(MTTouchStateNotTracking), Int32(MTTouchStateLingerInRange), Int32(MTTouchStateOutOfRange): self = .lifted
        default: self = .unknown
        }
    }
}
