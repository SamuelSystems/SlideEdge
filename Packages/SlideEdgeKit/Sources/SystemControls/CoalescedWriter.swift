import Foundation

/// Applies only the latest submitted value, at most once per interval, on a serial queue.
/// Keeps slow outputs (USB audio, external displays) from falling behind a fast slide.
final class CoalescedWriter: @unchecked Sendable {
    private let queue: DispatchQueue
    private let interval: TimeInterval
    private let write: (Double) -> Void

    // Confined to `queue`.
    private var pending: Double?
    private var flushScheduled = false
    private var lastWrite = DispatchTime(uptimeNanoseconds: 0)

    /// `write` runs on `queue`.
    init(queue: DispatchQueue, interval: TimeInterval = 1.0 / 60, write: @escaping (Double) -> Void) {
        self.queue = queue
        self.interval = interval
        self.write = write
    }

    func submit(_ value: Double) {
        queue.async { [self] in
            pending = value
            guard !flushScheduled else { return }
            flushScheduled = true
            queue.asyncAfter(deadline: max(lastWrite + interval, .now())) { [self] in
                flushScheduled = false
                guard let value = pending else { return }
                pending = nil
                write(value)
                lastWrite = .now()
            }
        }
    }

    /// Drops a value not yet written (e.g. the output device changed). Call on `queue`.
    func discardPending() {
        pending = nil
    }
}
