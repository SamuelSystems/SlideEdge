import CoreGraphics
import Foundation
import GestureEngine
import KeyActivity
import TouchInput

/// Runs one `GestureEngine` per device on a dedicated serial queue.
final class GesturePipeline: @unchecked Sendable {
    /// Receives the events of one frame, in order, with the pointer position sampled on that frame.
    typealias EventHandler = @Sendable ([GestureEvent], CGPoint?) -> Void

    private let queue = DispatchQueue(label: "SlideEdge.Gestures", qos: .userInteractive)
    private let onEvents: EventHandler
    private let keyActivity: KeyActivityMonitor

    // Confined to `queue`.
    private var config = GestureConfig()
    private var aspects: [UInt64: Double] = [:]
    private var engines: [UInt64: GestureEngine] = [:]
    private var deadlines: [UInt64: DispatchWorkItem] = [:]

    init(keyActivity: KeyActivityMonitor, onEvents: @escaping EventHandler) {
        self.keyActivity = keyActivity
        self.onEvents = onEvents
    }

    func update(config: GestureConfig) {
        queue.async { [self] in
            self.config = config
            for id in engines.keys {
                engines[id]?.config = deviceConfig(for: id)
            }
        }
    }

    func update(devices: [TouchDeviceInfo]) {
        queue.async { [self] in
            aspects = Dictionary(uniqueKeysWithValues: devices.compactMap { device in
                device.width > 0 && device.height > 0 ? (device.id, device.width / device.height) : nil
            })
            for id in engines.keys where !devices.contains(where: { $0.id == id }) {
                emit(engines[id]?.reset() ?? [])
                engines[id] = nil
            }
            for id in engines.keys {
                engines[id]?.config = deviceConfig(for: id)
            }
        }
    }

    /// Ends every slide in progress (e.g. when SlideEdge is turned off).
    func reset() {
        queue.async { [self] in
            for id in engines.keys {
                emit(engines[id]?.reset() ?? [])
            }
        }
    }

    /// Called on the multitouch thread.
    func process(_ frame: TouchFrame) {
        queue.async { [self] in
            let id = frame.deviceID
            let samples = frame.touches.compactMap { touch in
                touch.phase.isContact ? TouchSample(id: touch.id, x: touch.x, y: touch.y) : nil
            }
            var engine = engines[id] ?? GestureEngine(config: deviceConfig(for: id))
            let context = samples.isEmpty ? GestureContext() : currentContext(frameTime: frame.timestamp)
            emit(engine.process(samples, at: frame.timestamp, context: context))
            engines[id] = engine
            scheduleDeadline(for: id, now: frame.timestamp)
        }
    }

    private func deviceConfig(for deviceID: UInt64) -> GestureConfig {
        var config = config
        if let aspect = aspects[deviceID] { config.surfaceAspect = aspect }
        return config
    }

    /// Ends a slide after the grace period even if MultitouchSupport stops sending frames.
    private func scheduleDeadline(for id: UInt64, now: Double) {
        deadlines[id]?.cancel()
        deadlines[id] = nil
        guard let deadline = engines[id]?.nextDeadline else { return }
        let work = DispatchWorkItem { [self] in
            deadlines[id] = nil
            guard var engine = engines[id] else { return }
            emit(engine.tick(at: deadline))
            engines[id] = engine
        }
        deadlines[id] = work
        queue.asyncAfter(deadline: .now() + max(deadline - now, 0) + 0.002, execute: work)
    }

    private func emit(_ events: [GestureEvent]) {
        guard !events.isEmpty else { return }
        // Sampled here, on the frame that produced the events: by the time the main thread
        // handles them the pointer may already have moved.
        onEvents(events, CGEvent(source: nil)?.location)
    }

    private func currentContext(frameTime: Double) -> GestureContext {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return GestureContext(
            modifierHeld: flags.contains(.maskSecondaryFn) || flags.contains(.maskAlternate),
            preciseModifierHeld: flags.contains(.maskShift) && flags.contains(.maskAlternate),
            // Key times use the uptime clock; express them as an age in the frame clock.
            lastKeyDown: keyActivity.secondsSinceLastKeyDown().map { frameTime - $0 }
        )
    }
}
