import Foundation
import os
import TouchInput

/// UI-facing view of the touch devices. Frames are only forwarded while the debug window is open.
@MainActor
final class TouchMonitor: ObservableObject {
    @Published private(set) var devices: [TouchDeviceInfo] = []
    @Published private(set) var status: TouchInputStatus = .stopped
    @Published private(set) var latestFrames: [UInt64: TouchFrame] = [:]
    @Published private(set) var frameRates: [UInt64: Int] = [:]

    nonisolated let relay = FrameRelay()

    func update(devices: [TouchDeviceInfo], status: TouchInputStatus) {
        self.devices = devices
        self.status = status
    }

    func setVisualizing(_ visualizing: Bool) {
        relay.setEnabled(visualizing)
        if !visualizing {
            latestFrames = [:]
            frameRates = [:]
        }
    }

    func flush() {
        let snapshot = relay.drain()
        latestFrames.merge(snapshot.frames) { $1 }
        frameRates.merge(snapshot.rates) { $1 }
    }
}

/// Lock-protected mailbox between the multitouch thread and the main thread.
/// Keeps only the latest frame per device, so the UI never falls behind the sensor.
final class FrameRelay: Sendable {
    private struct State {
        var enabled = false
        var flushScheduled = false
        var frames: [UInt64: TouchFrame] = [:]
        var rates: [UInt64: Int] = [:]
        var windowStart: [UInt64: Double] = [:]
        var windowCount: [UInt64: Int] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func setEnabled(_ enabled: Bool) {
        state.withLock { $0 = State(enabled: enabled) }
    }

    /// Returns true when the caller must schedule a flush on the main thread.
    func push(_ frame: TouchFrame) -> Bool {
        state.withLock { state in
            guard state.enabled else { return false }
            let id = frame.deviceID
            state.frames[id] = frame

            let start = state.windowStart[id] ?? frame.timestamp
            let count = (state.windowCount[id] ?? 0) + 1
            if frame.timestamp - start >= 1 {
                state.rates[id] = count
                state.windowStart[id] = frame.timestamp
                state.windowCount[id] = 0
            } else {
                state.windowStart[id] = start
                state.windowCount[id] = count
            }

            guard !state.flushScheduled else { return false }
            state.flushScheduled = true
            return true
        }
    }

    func drain() -> (frames: [UInt64: TouchFrame], rates: [UInt64: Int]) {
        state.withLock { state in
            state.flushScheduled = false
            defer { state.frames = [:] }
            return (state.frames, state.rates)
        }
    }
}
